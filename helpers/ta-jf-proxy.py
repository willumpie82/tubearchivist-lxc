#!/usr/bin/env python3
"""TubeArchivist Jellyfin Proxy - Name to ID translation + URL rewriting with debug output + direct image serving"""
import os
import sys
import logging
import json
import subprocess
from flask import Flask, jsonify, request, send_file, make_response
from pathlib import Path

app = Flask(__name__)
TA_API_URL = "http://localhost/api"
TA_API_TOKEN = "15992a2bb1510a91a17d3067c4ee92bbca9587f9"
TA_HOST = os.environ.get("TA_HOST", "192.168.1.186")
LOG_FILE = "/var/log/ta-jf-proxy.log"

# Setup logging with debug output
logging.basicConfig(
    level=logging.DEBUG,
    format="%(asctime)s - %(levelname)s - %(funcName)s - %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

def query_elasticsearch(es_index, search_field, search_value):
    """Query Elasticsearch for ID with debug output"""
    try:
        query = {"query": {"match": {search_field: search_value}}}
        cmd = ["curl", "-s", "-X", "POST", "-H", "Content-Type: application/json",
               "-d", json.dumps(query), f"http://localhost:9200/{es_index}/_search?size=1"]
        
        logger.debug(f"ES Query: {es_index} - {search_field}={search_value}")
        
        result = subprocess.run(cmd, capture_output=True, timeout=5, text=True)
        if result.returncode != 0:
            logger.error(f"ES query failed: {result.stderr}")
            return None
        
        data = json.loads(result.stdout)
        hits = data.get("hits", {}).get("hits", [])
        if hits:
            found_id = hits[0].get("_id")
            logger.debug(f"ES found ID: {found_id}")
            return found_id
        
        logger.warning(f"ES no results for {search_field}={search_value}")
        return None
    except Exception as e:
        logger.error(f"ES query error: {e}")
        return None

def rewrite_urls(data, path=""):
    """Enrich TA metadata for Jellyfin with standardized fields
    
    Jellyfin expects certain fields to properly display metadata.
    We extract from TA response and add/reformat for Jellyfin compatibility.
    """
    if isinstance(data, dict):
        # For video responses
        if "title" in data:
            # Ensure key fields are present
            enriched = data.copy()
            
            # Jellyfin-friendly duration (in seconds)
            if "player" in data and "duration" in data["player"]:
                enriched["duration"] = data["player"]["duration"]
                enriched["duration_str"] = data["player"].get("duration_str", "")
            
            # Ensure published/aired date is present
            if "published" in data and "date_published" not in enriched:
                try:
                    pub_date = data["published"].split("T")[0]  # YYYY-MM-DD
                    enriched["date_published"] = pub_date
                except:
                    pass
            
            # Extract channel info if available
            if "channel" in data and isinstance(data["channel"], dict):
                enriched["series"] = data["channel"].get("channel_name", "")
                enriched["studio"] = data["channel"].get("channel_name", "")
            
            # Ensure description is available
            if "description" not in enriched and "comments" not in enriched:
                enriched["description"] = data.get("description", "")
            
            # Add genre
            if "genre" not in enriched:
                enriched["genre"] = "YouTube"
            
            logger.debug(f"Enriched video metadata with fields: {list(enriched.keys())}")
            return enriched
        
        # For channel responses  
        if "channel_name" in data:
            enriched = data.copy()
            
            # Standardize channel name fields
            if "name" not in enriched:
                enriched["name"] = data.get("channel_name", "")
            
            # Add series info
            if "series" not in enriched:
                enriched["series"] = data.get("channel_name", "")
            
            logger.debug(f"Enriched channel metadata: {data.get('channel_name')}")
            return enriched
    
    # Return data as-is for non-dict responses
    return data

def proxy_to_ta(endpoint):
    """Forward to TA API with debug output"""
    try:
        url = f"{TA_API_URL}/{endpoint}"
        cmd = ["curl", "-s", "-H", f"Authorization: Token {TA_API_TOKEN}",
               "-H", "Content-Type: application/json", url]
        
        logger.debug(f"TA request: {endpoint}")
        
        result = subprocess.run(cmd, capture_output=True, timeout=10, text=True)
        if result.returncode == 0:
            response = json.loads(result.stdout)
            logger.debug(f"TA response keys: {list(response.keys()) if isinstance(response, dict) else 'list'}")
            # Return TA response as-is - Jellyfin plugin expects original field names
            return rewrite_urls(response)
        
        logger.error(f"TA API error for {endpoint}")
        return {"error": "TA API error"}
    except Exception as e:
        logger.error(f"Proxy error: {e}")
        return {"error": str(e)}

@app.route("/api/channel/<name>/", methods=["GET"])
def get_channel(name):
    logger.info(f"[REQUEST] Channel '{name}' from {request.remote_addr}")
    
    cid = query_elasticsearch("ta_channel", "channel_name", name)
    if not cid:
        logger.warning(f"[NOTFOUND] Channel '{name}' not found in Elasticsearch")
        return jsonify({"error": "Not found"}), 404
    
    logger.info(f"[TRANSLATE] Channel '{name}' → ID: {cid}")
    result = proxy_to_ta(f"channel/{cid}/")
    
    if "error" in result:
        logger.error(f"[ERROR] Failed to get channel data for {cid}")
        return jsonify(result), 500
    
    # Enrich with Jellyfin-friendly metadata
    enriched_result = rewrite_urls(result, "channel")
    
    # Add Jellyfin collection fields
    if isinstance(enriched_result, dict):
        if "genre" not in enriched_result:
            enriched_result["genre"] = "YouTube"
        if "type" not in enriched_result:
            enriched_result["type"] = "Series"
    
    logger.debug(f"[RESPONSE] Returning {len(json.dumps(enriched_result))} bytes with enriched metadata")
    return jsonify(enriched_result)

@app.route("/api/video/<path:path>/", methods=["GET"])
def get_video(path):
    logger.info(f"[REQUEST] Video '{path}' from {request.remote_addr}")
    
    title = path.split("/|/")[0].replace("/", " ").strip()
    vid = query_elasticsearch("ta_video", "title", title)
    if not vid:
        logger.warning(f"[NOTFOUND] Video '{title}' not found in Elasticsearch")
        return jsonify({"error": "Not found"}), 404
    
    logger.info(f"[TRANSLATE] Video '{title}' → ID: {vid}")
    result = proxy_to_ta(f"video/{vid}/")
    
    if "error" in result:
        logger.error(f"[ERROR] Failed to get video data for {vid}")
        return jsonify(result), 500
    
    # Enrich with Jellyfin-friendly metadata
    enriched_result = rewrite_urls(result, "video")
    
    # Add extra Jellyfin fields
    if isinstance(enriched_result, dict):
        # Ensure episode count/season info
        if "episode" not in enriched_result:
            enriched_result["episode"] = 1
        if "season" not in enriched_result and "published" in enriched_result:
            try:
                year = enriched_result["published"].split("-")[0]
                enriched_result["season"] = int(year)
            except:
                enriched_result["season"] = 1
    
    logger.debug(f"[RESPONSE] Returning {len(json.dumps(enriched_result))} bytes with enriched metadata")
    return jsonify(enriched_result)

@app.route("/debug/", methods=["GET"])
def debug_info():
    """Debug endpoint for troubleshooting Jellyfin integration"""
    logger.info(f"[DEBUG] Debug info requested from {request.remote_addr}")
    
    return jsonify({
        "status": "ta-jf-proxy running",
        "ta_host": TA_HOST,
        "ta_api_url": TA_API_URL,
        "endpoints": {
            "channel": "/api/channel/<name>/",
            "video": "/api/video/<title>/",
            "image": "/api/image/<path>",
            "health": "/health/"
        },
        "test_urls": {
            "channel_metadata": f"http://{TA_HOST}:8081/api/channel/Tomorrowland/",
            "channel_image": f"http://{TA_HOST}:8081/api/image/channels/UCsN8M73DMWa8SPp5o_0IAQQ_thumb.jpg",
            "video_metadata": f"http://{TA_HOST}:8081/api/video/Wade/",
            "health_check": f"http://{TA_HOST}:8081/health/"
        },
        "jellyfin_config": {
            "api_url": f"http://{TA_HOST}:8081",
            "note": "Use PROXY URL, not direct TA API"
        }
    })

@app.route("/health/", methods=["GET"])
def health():
    logger.debug(f"Health check from {request.remote_addr}")
    return jsonify({"status": "ok"})

@app.route("/cache/<path:filepath>", methods=["GET"])
def serve_cache(filepath):
    """Serve cached media files (for Jellyfin plugin compatibility)
    
    Jellyfin plugin does: TubeArchivistUrl + /cache/...
    If TubeArchivistUrl is our proxy (192.168.1.186:8081),
    this endpoint handles those requests
    """
    logger.info(f"[CACHE_REQUEST] /cache/{filepath} from {request.remote_addr}")
    
    # Sanitize path to prevent directory traversal
    if ".." in filepath or filepath.startswith("/"):
        logger.warning(f"[CACHE_BLOCKED] Attempted path traversal: {filepath}")
        return jsonify({"error": "Invalid path"}), 403
    
    image_path = Path("/cache") / filepath
    
    if not image_path.exists():
        logger.warning(f"[CACHE_404] File not found: {image_path}")
        return jsonify({"error": "Not found"}), 404
    
    if not image_path.is_file():
        logger.warning(f"[CACHE_BLOCKED] Path is not a file: {image_path}")
        return jsonify({"error": "Invalid"}), 403
    
    try:
        logger.debug(f"[CACHE_SERVE] Sending: {image_path}")
        response = make_response(send_file(str(image_path), mimetype="image/jpeg"))
        # Set cache headers for 1 year
        response.headers["Cache-Control"] = "public, max-age=31536000, immutable"
        response.headers["ETag"] = f"\"{image_path.stat().st_mtime}-{image_path.stat().st_size}\""
        return response
    except Exception as e:
        logger.error(f"[CACHE_ERROR] Failed to serve {image_path}: {e}")
        return jsonify({"error": str(e)}), 500

@app.route("/api/image/<path:filepath>", methods=["GET"])
def serve_image(filepath):
    """Serve cached images directly (channels, videos, etc)"""
    logger.info(f"[IMAGE_REQUEST] {filepath} from {request.remote_addr}")
    
    # Sanitize path to prevent directory traversal
    if ".." in filepath or filepath.startswith("/"):
        logger.warning(f"[IMAGE_BLOCKED] Attempted path traversal: {filepath}")
        return jsonify({"error": "Invalid path"}), 403
    
    image_path = Path("/cache") / filepath
    
    if not image_path.exists():
        logger.warning(f"[IMAGE_404] File not found: {image_path}")
        return jsonify({"error": "Not found"}), 404
    
    if not image_path.is_file():
        logger.warning(f"[IMAGE_BLOCKED] Path is not a file: {image_path}")
        return jsonify({"error": "Invalid"}), 403
    
    try:
        logger.debug(f"[IMAGE_SERVE] Sending: {image_path}")
        response = make_response(send_file(str(image_path), mimetype="image/jpeg"))
        # Set cache headers for 1 year
        response.headers["Cache-Control"] = "public, max-age=31536000, immutable"
        response.headers["ETag"] = f"\"{image_path.stat().st_mtime}-{image_path.stat().st_size}\""
        return response
    except Exception as e:
        logger.error(f"[IMAGE_ERROR] Failed to serve {image_path}: {e}")
        return jsonify({"error": str(e)}), 500

@app.before_request
def log_request():
    """Log all incoming requests"""
    logger.debug(f"→ {request.method} {request.path}")

@app.after_request
def log_response(response):
    """Log all outgoing responses"""
    logger.debug(f"← {response.status_code}")
    return response

if __name__ == "__main__":
    logger.info("="*50)
    logger.info("TubeArchivist Jellyfin Proxy Starting")
    logger.info(f"TA_HOST: {TA_HOST}")
    logger.info(f"TA_API_URL: {TA_API_URL}")
    logger.info("="*50)
    app.run(host="0.0.0.0", port=8081, debug=False)
