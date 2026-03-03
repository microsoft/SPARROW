"""
FTP server for camera feed: accepts FTP connections,
authenticates a single user, and stores uploaded files in /app/images.
"""

import os
import logging
from pyftpdlib.authorizers import DummyAuthorizer
from pyftpdlib.handlers import FTPHandler
from pyftpdlib.servers import FTPServer

# Configuration Paths
SAVE_DIR = "/app/images"
LOG_DIR = "/app/logs"
os.makedirs(LOG_DIR, exist_ok=True)
os.makedirs(SAVE_DIR, exist_ok=True)
LOG_FILE = os.path.join(LOG_DIR, "ftp_server.log")

# Setup Logging & Folders
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

FTP_USER = os.getenv("FTP_USER", "camera")
FTP_PASS = os.getenv("FTP_PASS")
FTP_PORT = 21

class CustomFTPHandler(FTPHandler):
    permit_foreign_addresses = True

    def on_connect(self):
        logger.info(f"New connection from {self.remote_ip}:{self.remote_port}")

    def on_disconnect(self):
        logger.info(f"Disconnected: {self.remote_ip}")

    def on_login(self, username):
        logger.info(f"User logged in: {username} from {self.remote_ip}")

    def on_login_failed(self, username, password):
        logger.warning(f"Failed login attempt: username={username} ip={self.remote_ip}")

    def on_file_received(self, file_path):
        logger.info(f"File received and saved: {file_path}")

    def on_incomplete_file_received(self, file_path):
        logger.warning(f"Incomplete file received (removed): {file_path}")


def main():
    authorizer = DummyAuthorizer()
    authorizer.add_user(FTP_USER, FTP_PASS, SAVE_DIR, perm="elradfmw")

    handler = CustomFTPHandler
    handler.authorizer = authorizer
    handler.banner = "Reolink FTP server ready."

    address = ("0.0.0.0", FTP_PORT)
    server = FTPServer(address, handler)

    # Connection limits
    server.max_cons = 256
    server.max_cons_per_ip = 10

    logger.info(f"FTP server listening on 0.0.0.0:{FTP_PORT}, saving to {SAVE_DIR}")
    server.serve_forever()


if __name__ == "__main__":
    main()
