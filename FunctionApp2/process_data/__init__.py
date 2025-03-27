import logging
import os
from math import ceil

import azure.functions as func
import pymssql
import requests


def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("AI Processor HTTP Function triggered.")

    try:
        ai_endpoint = os.environ.get("AI_ENDPOINT")
        ai_key = os.environ.get("AI_KEY")
        adf_conn_params = {
            "server": os.environ.get("ADF_SQL_SERVER"),
            "database": os.environ.get("ADF_SQL_DB"),
            "user": os.environ.get("ADF_SQL_USER"),
            "password": os.environ.get("ADF_SQL_PASSWORD"),
        }
        ai_conn_params = {
            "server": os.environ.get("AI_SQL_SERVER"),
            "database": os.environ.get("AI_SQL_DB"),
            "user": os.environ.get("AI_SQL_USER"),
            "password": os.environ.get("AI_SQL_PASSWORD"),
        }

        if not all(
            [ai_endpoint, ai_key]
            + list(adf_conn_params.values())
            + list(ai_conn_params.values())
        ):
            logging.error("Missing required environment variables.")
            return func.HttpResponse("Missing configuration", status_code=500)

        # Connect to ADF DB
        adf_conn = pymssql.connect(**adf_conn_params)
        adf_cursor = adf_conn.cursor(as_dict=True)
        adf_cursor.execute(
            "SELECT id, text_column FROM SourceTable WHERE processed = 0"
        )
        rows = adf_cursor.fetchall()

        if not rows:
            logging.info("No new data to process.")
            return func.HttpResponse("No new data to process.", status_code=200)

        documents = [
            {"id": str(row["id"]), "language": "en", "text": row["text_column"]}
            for row in rows
        ]

        # Call Azure AI Language Service
        results = []
        batch_size = 10
        num_batches = ceil(len(documents) / batch_size)

        for i in range(num_batches):
            batch = documents[i * batch_size : (i + 1) * batch_size]

            response = requests.post(
                url=f"{ai_endpoint}/text/analytics/v3.1/sentiment",
                headers={
                    "Ocp-Apim-Subscription-Key": ai_key,
                    "Content-Type": "application/json",
                },
                json={"documents": batch},
            )

            if response.status_code != 200:
                logging.error(
                    f"AI API call failed on batch {i + 1}: {response.status_code} - {response.text}"
                )
                return func.HttpResponse("AI service error", status_code=500)

            result = response.json()
            if "documents" not in result:
                logging.error(f"Unexpected AI response: {result}")
                return func.HttpResponse("Invalid AI response", status_code=500)

            results.extend(result["documents"])

        # Save results to AI DB
        ai_conn = pymssql.connect(**ai_conn_params)
        ai_cursor = ai_conn.cursor()
        for doc in results:
            ai_cursor.execute(
                "INSERT INTO SentimentResults (record_id, sentiment, confidence) VALUES (%s, %s, %s)",
                (
                    doc["id"],
                    doc["sentiment"],
                    doc["confidenceScores"]["positive"],
                ),
            )
        ai_conn.commit()

        # Mark processed in ADF DB
        ids = [str(row["id"]) for row in rows]
        id_list = ",".join(ids)
        adf_cursor.execute(
            f"UPDATE SourceTable SET processed = 1 WHERE id IN ({id_list})"
        )
        adf_conn.commit()

        msg = f"Sentiment analysis complete for {len(results)} records."
        logging.info(msg)
        return func.HttpResponse(msg, status_code=200)

    except Exception as e:
        logging.error(f"Processing failed: {e}")
        return func.HttpResponse("Processing failed.", status_code=500)
