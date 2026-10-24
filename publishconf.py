import sys
from pathlib import Path

root_path = Path(__file__).resolve().parent
if str(root_path) not in sys.path:
    sys.path.insert(0, str(root_path))

from pelicanconf import *

SITEURL = "https://2shell2furio.us"
RELATIVE_URLS = False
DELETE_OUTPUT_DIRECTORY = True
