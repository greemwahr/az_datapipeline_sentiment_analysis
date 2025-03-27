import logging
import os

import azure.functions as func
import pyodbc
import requests


def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("AI Processor HTTP Function triggered.")

    try:
        ai_endpoint = os.environ.get("AI_ENDPOINT")
        ai_key = os.environ.get("AI_KEY")
        adf_conn_str = os.environ.get("ADF_SQL_CONN_STRING")
        ai_conn_str = os.environ.get("AI_SQL_CONN_STRING")

        if not all([ai_endpoint, ai_key, adf_conn_str, ai_conn_str]):
            logging.error("Missing required environment variables.")
            return func.HttpResponse("Missing configuration", status_code=500)

        # Connect to ADF DB
        adf_conn = pyodbc.connect(adf_conn_str)
        cursor = adf_conn.cursor()
        cursor.execute(
            "SELECT id, text_column FROM SourceTable WHERE processed = 0"
        )
        rows = cursor.fetchall()

        if not rows:
            logging.info("No new data to process.")
            return func.HttpResponse("No new data to process.", status_code=200)

        documents = [
            {"id": str(row.id), "language": "en", "text": row.text_column}
            for row in rows
        ]

        # Call Azure AI Language Service
        response = requests.post(
            url=f"{ai_endpoint}/text/analytics/v3.1/sentiment",
            headers={
                "Ocp-Apim-Subscription-Key": ai_key,
                "Content-Type": "application/json",
            },
            json={"documents": documents},
        )

        if response.status_code != 200:
            logging.error(
                f"AI API call failed: {response.status_code} - {response.text}"
            )
            return func.HttpResponse("AI service error", status_code=500)

        result = response.json()
        if "documents" not in result:
            logging.error(f"Unexpected AI response: {result}")
            return func.HttpResponse("Invalid AI response", status_code=500)

        # Save results to AI DB
        ai_conn = pyodbc.connect(ai_conn_str)
        ai_cursor = ai_conn.cursor()
        for doc in result["documents"]:
            ai_cursor.execute(
                "INSERT INTO SentimentResults (record_id, sentiment, confidence) VALUES (?, ?, ?)",
                doc["id"],
                doc["sentiment"],
                doc["confidenceScores"]["positive"],
            )
        ai_conn.commit()

        # Mark processed in ADF DB
        ids = [str(row.id) for row in rows]
        id_list = ",".join(ids)
        cursor.execute(
            f"UPDATE SourceTable SET processed = 1 WHERE id IN ({id_list})"
        )
        adf_conn.commit()

        msg = f"Sentiment analysis complete for {len(result['documents'])} records."
        logging.info(msg)
        return func.HttpResponse(msg, status_code=200)

    except Exception as e:
        logging.error(f"Processing failed: {e}")
        return func.HttpResponse("Processing failed.", status_code=500)
