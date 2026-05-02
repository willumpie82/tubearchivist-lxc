#!/bin/bash
export PYTHONPATH="/app:$PYTHONPATH"
cd /opt/ta-helper
source /app/venv/bin/activate
python3 ta-helper-simple.py 2>/dev/null
