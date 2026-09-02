import os

import requests
from flask import Flask, jsonify, render_template_string, request

app = Flask(__name__)

REPLAYHUB_URL = 'http://ftp.slippi:9876'
BRACKET_URL = 'https://www.start.gg/tournament/ladder-18/event/'

# Flask service running locally that knows the start.gg entrants.
BRACKET_API_URL = os.environ.get(
    "REPORT_API_URL",
    "meleenium.slippi"
)


HTML = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Station Check-In</title>

    <style>
        body {
            font-family: Arial, sans-serif;
            background: #f4f4f4;
            margin: 0;
            padding: 0;
        }

        .container {
            max-width: 500px;
            margin: 80px auto;
            background: white;
            padding: 30px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0, 0, 0, 0.1);
        }

        h1 {
            text-align: center;
            margin-bottom: 30px;
        }

        label {
            display: block;
            margin-top: 15px;
            margin-bottom: 5px;
            font-weight: bold;
        }

        select,
        input,
        button {
            width: 100%;
            box-sizing: border-box;
            padding: 12px;
            font-size: 16px;
            border-radius: 5px;
        }

        select,
        input {
            border: 1px solid #ccc;
        }

        button {
            margin-top: 25px;
            border: none;
            background: #007bff;
            color: white;
            cursor: pointer;
        }

        button:hover {
            background: #0056b3;
        }

        button:disabled {
            background: #999;
            cursor: not-allowed;
        }

        #message {
            margin-top: 20px;
            padding: 12px;
            border-radius: 5px;
            display: none;
        }

        .success {
            background: #d4edda;
            color: #155724;
        }

        .error {
            background: #f8d7da;
            color: #721c24;
        }

        .bracket {
            margin-top: 30px;
            text-align: center;
        }

        .bracket a {
            color: #007bff;
            text-decoration: none;
        }

        .bracket a:hover {
            text-decoration: underline;
        }
    </style>
</head>

<body>
    <div class="container">
        <h1>Station Check-In</h1>

        <label for="nickname">Player Nickname</label>
        <input
            type="text"
            id="nickname"
            placeholder="Enter player nickname"
        >

        <label for="station">Station</label>
        <select id="station">
            <option value="">Loading stations...</option>
        </select>

        <label for="port">Port Number</label>
        <input
            type="number"
            id="port"
            placeholder="Enter port number"
            min="1"
            max="65535"
        >

        <button id="checkInButton" onclick="checkIn()">
            Check In
        </button>

        <div id="message"></div>

        <div class="bracket">
            <a href="{{ bracket_url }}" target="_blank">
                View Bracket
            </a>
        </div>
    </div>

    <script>
        async function loadStations() {
            const stationSelect =
                document.getElementById("station");

            try {
                const response = await fetch("/stations");
                const data = await response.json();

                if (!response.ok) {
                    throw new Error(
                        data.error || "Failed to load stations"
                    );
                }

                stationSelect.innerHTML = "";

                data.stations.forEach(station => {
                    const option =
                        document.createElement("option");

                    option.value = station;
                    option.textContent = station;

                    stationSelect.appendChild(option);
                });

            } catch (error) {
                stationSelect.innerHTML =
                    '<option value="">Failed to load stations</option>';

                showMessage(error.message, false);
            }
        }


        async function checkIn() {
            const nickname =
                document.getElementById("nickname").value.trim();

            const station =
                document.getElementById("station").value;

            const port =
                document.getElementById("port").value;

            const button =
                document.getElementById("checkInButton");

            if (!nickname) {
                showMessage(
                    "Please enter the player nickname.",
                    false
                );
                return;
            }

            if (!station) {
                showMessage(
                    "Please select a station.",
                    false
                );
                return;
            }

            if (!port) {
                showMessage(
                    "Please enter a port number.",
                    false
                );
                return;
            }

            button.disabled = true;
            button.textContent = "Checking in...";

            try {
                const response = await fetch("/check-in", {
                    method: "POST",
                    headers: {
                        "Content-Type": "application/json"
                    },
                    body: JSON.stringify({
                        nickname: nickname,
                        station: station,
                        port: Number(port)
                    })
                });

                const data = await response.json();

                if (!response.ok) {
                    throw new Error(
                        data.error || "Check-in failed"
                    );
                }

                showMessage(
                    "Successfully checked in " +
                    nickname +
                    " (entrant ID " +
                    data.entrant_id +
                    ") on port " +
                    port +
                    ".",
                    true
                );

            } catch (error) {
                showMessage(
                    error.message,
                    false
                );

            } finally {
                button.disabled = false;
                button.textContent = "Check In";
            }
        }


        function showMessage(message, success) {
            const element =
                document.getElementById("message");

            element.textContent = message;

            element.className = success
                ? "success"
                : "error";

            element.style.display = "block";
        }


        loadStations();
    </script>
</body>
</html>
"""


@app.route("/")
def index():
    return render_template_string(
        HTML,
        bracket_url=BRACKET_URL
    )


# ============================================================
# Get stations from ReplayHub
# ============================================================

@app.route("/stations", methods=["GET"])
def stations():
    try:
        response = requests.get(
            REPLAYHUB_URL,
            timeout=10
        )

        response.raise_for_status()

        data = response.json()

        if isinstance(data, list):
            station_names = data
        else:
            station_names = data["stations"]

        return jsonify({
            "stations": station_names
        })

    except Exception as e:
        return jsonify({
            "error": str(e)
        }), 500


# ============================================================
# Look up entrant ID from the other Flask application
# ============================================================

def get_entrant_id(nickname):
    """
    Ask the bracket Flask service for the start.gg entrant ID
    associated with a nickname.

    Expected endpoint on the bracket service:

        GET /entrant/<nickname>

    Expected response:

        {
            "entrant_id": "123456",
            "nickname": "Player"
        }
    """

    response = requests.get(
        f"{BRACKET_API_URL}/entrant/{requests.utils.quote(nickname)}",
        timeout=10
    )

    response.raise_for_status()

    data = response.json()

    entrant_id = data.get("entrant_id")

    if not entrant_id:
        raise RuntimeError(
            f"No entrant ID found for nickname '{nickname}'"
        )

    return str(entrant_id)


# ============================================================
# Check in
# ============================================================

@app.route("/check-in", methods=["POST"])
def check_in():
    try:
        data = request.get_json()

        if not data:
            raise ValueError(
                "Request body must contain JSON"
            )

        nickname = data.get("nickname", "").strip()
        station = data.get("station", "").strip()
        port = int(data.get("port"))

        if not nickname:
            raise ValueError(
                "Nickname is required"
            )

        if not station:
            raise ValueError(
                "Station is required"
            )

        if not 1 <= port <= 65535:
            raise ValueError(
                "Port must be between 1 and 65535"
            )

        # ----------------------------------------------------
        # Get entrant ID from the local bracket service
        # ----------------------------------------------------

        entrant_id = get_entrant_id(
            nickname
        )

        # ----------------------------------------------------
        # Send check-in to ReplayHub
        # ----------------------------------------------------

        response = requests.post(
            REPLAYHUB_URL,
            json={
                "station": station,
                "port": port,
                "entrant_id": entrant_id,
                "nickname": nickname
            },
            timeout=10
        )

        response.raise_for_status()

        return jsonify({
            "success": True,
            "nickname": nickname,
            "entrant_id": entrant_id,
            "station": station,
            "port": port,
            "response": (
                response.json()
                if response.content
                else None
            )
        }), 200

    except requests.HTTPError as e:
        return jsonify({
            "success": False,
            "error": str(e)
        }), 500

    except Exception as e:
        return jsonify({
            "success": False,
            "error": str(e)
        }), 500


if __name__ == "__main__":
    app.run(
        host="0.0.0.0",
        port=5003,
        threaded=True
    )

