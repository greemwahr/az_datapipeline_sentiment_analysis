import json
import logging
import os

import azure.functions as func
import requests


def main(mytimer: func.TimerRequest) -> None:
    logging.info("Timer trigger function executed at: %s", mytimer.utc_now)

    # Use a specific hotel_id; alternatively pull from an environment variable.
    hotel_id = os.environ.get("HOTEL_ID", "1676161")

    # API URL for Booking.com reviews
    url = "https://booking-com.p.rapidapi.com/v1/hotels/reviews"

    # Query parameters – using the provided hotel_id.
    querystring = {
        "page_number": "0",
        "language_filter": "en-gb,de,fr",
        "hotel_id": hotel_id,
        "locale": "en-gb",
        "sort_type": "SORT_MOST_RELEVANT",
        "customer_type": "solo_traveller,review_category_group_of_friends",
    }

    # Setup headers with the RapidAPI Key.
    headers = {
        "x-rapidapi-key": "c2b21c1503msh8ea19a235bd0da1p1f5377jsn973a8e9a76f5",
        "x-rapidapi-host": "booking-com.p.rapidapi.com",
    }

    try:
        response = requests.get(url, headers=headers, params=querystring)
        response.raise_for_status()
        data = response.json()
        logging.info("Retrieved hotel reviews: %s", json.dumps(data))
    except Exception as e:
        logging.error("Error calling the Booking.com API: %s", e)
