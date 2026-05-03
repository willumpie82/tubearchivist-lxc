#!/usr/bin/env python3
"""TubeArchivist Helper - Create human-readable hardlinks and NFO metadata"""
import os
import sys
import logging
import json
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path
from datetime import datetime, timedelta
from dotenv import load_dotenv

# Load secrets from file
SECRETS_FILE = "/etc/ta-helper/secrets.env"
if os.path.exists(SECRETS_FILE):
    load_dotenv(SECRETS_FILE)
else:
    # Fallback to environment variables if secrets file doesn't exist
    pass

SOURCE_FOLDER = "/mnt/media/arr/tubearchivist"
TARGET_FOLDER = "/mnt/media/library/youtube"
LOG_FILE = "/var/log/ta-helper.log"
ES_URL = "http://localhost:9200/ta_video/_search"
TA_API_URL = "http://localhost/api/v1/video"
TA_USERNAME = os.environ.get("TA_USERNAME", "admin")
TA_PASSWORD = os.environ.get("TA_PASSWORD", "changeme")
JF_API_URL = os.environ.get("JF_API_URL", "http://localhost:8081")
JF_API_KEY = os.environ.get("JF_API_KEY", "")

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

def mark_video_as_watched(video_id):
    """Mark video as watched and set for deletion after 1 day using curl"""
    try:
        url = f"{TA_API_URL}/{video_id}/"
        delete_date = (datetime.now() + timedelta(days=1)).strftime("%Y-%m-%d")
        
        payload = {
            "watched": True,
            "status": "delete",
            "date_downloaded": delete_date
        }
        
        cmd = [
            "curl", "-s", "-X", "PATCH",
            f"-u", f"{TA_USERNAME}:{TA_PASSWORD}",
            "-H", "Content-Type: application/json",
            "-d", json.dumps(payload),
            url
        ]
        
        result = subprocess.run(cmd, capture_output=True, timeout=5)
        
        if result.returncode == 0:
            logger.info(f"Marked {video_id} as watched (will auto-delete, library copy stays)")
            return True
        else:
            logger.warning(f"Failed to mark {video_id} as watched")
            return False
    except Exception as e:
        logger.error(f"Error marking {video_id} as watched: {e}")
        return False

def trigger_jellyfin_refresh():
    """Trigger Jellyfin library refresh for YouTube folder"""
    if not JF_API_KEY:
        logger.debug("No Jellyfin API key configured, skipping library refresh")
        return False
    
    try:
        # Trigger refresh via Jellyfin API
        url = f"{JF_API_URL}/emby/Library/Refresh?api_key={JF_API_KEY}"
        
        cmd = [
            "curl", "-s", "-X", "POST",
            "-H", "Content-Type: application/json",
            url
        ]
        
        result = subprocess.run(cmd, capture_output=True, timeout=10)
        
        if result.returncode == 0:
            response = result.stdout.decode().strip()
            # 404 means endpoint doesn't exist, other errors are connection issues
            if "404" in response or "Not Found" in response:
                logger.debug(f"Jellyfin refresh endpoint not found (Jellyfin may not be running)")
                return False
            elif result.returncode == 0:
                logger.info("Triggered Jellyfin library refresh")
                return True
        else:
            logger.debug(f"Jellyfin not available (connection refused or timeout)")
            return False
    except subprocess.TimeoutExpired:
        logger.debug("Jellyfin refresh timed out (server may be unavailable)")
        return False
    except Exception as e:
        logger.debug(f"Jellyfin refresh skipped: {e}")
        return False

def create_nfo_file(nfo_path, video_id, title, channel_name, description, upload_date):
    """Create NFO metadata file for Jellyfin"""
    try:
        root = ET.Element("video")
        
        title_elem = ET.SubElement(root, "title")
        title_elem.text = title
        
        plot_elem = ET.SubElement(root, "plot")
        plot_elem.text = f"Channel: {channel_name}\n\n{description}" if description else f"Channel: {channel_name}"
        
        aired_elem = ET.SubElement(root, "aired")
        aired_elem.text = upload_date
        
        premiered_elem = ET.SubElement(root, "premiered")
        premiered_elem.text = upload_date
        
        ta_id_elem = ET.SubElement(root, "uniqueid")
        ta_id_elem.set("type", "tubearchivist")
        ta_id_elem.text = video_id
        
        tree = ET.ElementTree(root)
        tree.write(str(nfo_path), encoding="utf-8", xml_declaration=True)
        
        return True
    except Exception as e:
        logger.error(f"Error creating NFO file {nfo_path}: {e}")
        return False

def query_elasticsearch():
    """Query Elasticsearch for all videos"""
    try:
        cmd = ["curl", "-s", f"{ES_URL}?size=10000"]
        result = subprocess.run(cmd, capture_output=True, timeout=5)
        
        if result.returncode == 0:
            return json.loads(result.stdout.decode())
        else:
            logger.warning(f"Elasticsearch query failed")
            return {"hits": {"hits": []}}
    except Exception as e:
        logger.error(f"Error querying Elasticsearch: {e}")
        return {"hits": {"hits": []}}

def main():
    logger.info("Starting ta-helper")
    
    try:
        Path(TARGET_FOLDER).mkdir(parents=True, exist_ok=True)
        
        data = query_elasticsearch()
        videos = data.get("hits", {}).get("hits", [])
        
        count_new = 0
        count_existing = 0
        count_marked = 0
        
        for video in videos:
            source = video.get("_source", {})
            video_id = video.get("_id", "")
            channel_name = source.get("channel", {}).get("channel_name", "Unknown")
            title = source.get("title", video_id)
            description = source.get("description", "")
            upload_date = source.get("upload_date", datetime.now().strftime("%Y-%m-%d"))
            media_url = source.get("media_url", "")
            
            if not media_url or not video_id:
                continue
            
            safe_title = title.replace("/", "-").replace("\\", "-").replace(":", "-")[:200]
            
            video_file = Path(SOURCE_FOLDER) / media_url
            
            if not video_file.exists():
                continue
            
            try:
                channel_folder = Path(TARGET_FOLDER) / channel_name
                channel_folder.mkdir(parents=True, exist_ok=True)
                
                link_path = channel_folder / f"{safe_title}.mp4"
                if not link_path.exists():
                    os.link(str(video_file), str(link_path))
                    logger.info(f"Created: {channel_name}/{safe_title}.mp4")
                    count_new += 1
                    
                    nfo_path = link_path.with_suffix(".nfo")
                    if create_nfo_file(nfo_path, video_id, title, channel_name, description, upload_date):
                        logger.info(f"Created NFO: {safe_title}.nfo")
                    
                    if mark_video_as_watched(video_id):
                        count_marked += 1
                else:
                    count_existing += 1
            except Exception as e:
                logger.error(f"Error creating link for {safe_title}: {e}")
        
        logger.info(f"Completed: {count_new} new, {count_existing} existing, {count_marked} as watched")
        
        # Trigger Jellyfin library refresh if new videos were added
        if count_new > 0:
            trigger_jellyfin_refresh()
        
        return 0
    
    except Exception as e:
        logger.error(f"Fatal error: {e}", exc_info=True)
        return 1

if __name__ == "__main__":
    sys.exit(main())
