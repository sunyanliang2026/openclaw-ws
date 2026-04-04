import os
from datetime import datetime
from flask import Flask, request, jsonify
from flask_cors import CORS
from detectors.image_detector import analyze_image
from detectors.text_detector import analyze_text

app = Flask(__name__)
CORS(app)

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
UPLOAD_DIR = os.path.join(BASE_DIR, "uploads")
RESULT_DIR = os.path.join(BASE_DIR, "results")

os.makedirs(UPLOAD_DIR, exist_ok=True)
os.makedirs(RESULT_DIR, exist_ok=True)


@app.route("/health", methods=["GET"])
def health():
    return jsonify({
        "success": True,
        "message": "service running"
    })


@app.route("/detect/image", methods=["POST"])
def detect_image():
    if "file" not in request.files:
        return jsonify({
            "success": False,
            "message": "no file uploaded"
        }), 400

    file = request.files["file"]

    if file.filename == "":
        return jsonify({
            "success": False,
            "message": "empty filename"
        }), 400

    timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
    filename = f"{timestamp}_{file.filename}"
    save_path = os.path.join(UPLOAD_DIR, filename)
    file.save(save_path)

    result = analyze_image(save_path)
    if result.get("success"):
        result.setdefault("details", {})["filename"] = filename
        result["details"]["saved_path"] = save_path
    return jsonify(result)


@app.route("/detect/text", methods=["POST"])
def detect_text():
    data = request.get_json()

    if not data or "content" not in data:
        return jsonify({
            "success": False,
            "message": "no text content provided"
        }), 400

    content = data.get("content", "").strip()

    if not content:
        return jsonify({
            "success": False,
            "message": "text content is empty"
        }), 400

    result = analyze_text(content)
    return jsonify(result)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001, debug=True)
