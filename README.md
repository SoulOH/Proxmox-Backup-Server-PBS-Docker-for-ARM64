[中文文档](README_zh.md)

# Proxmox Backup Server (PBS) Docker for ARM64

This is a Proxmox Backup Server Docker image built specifically for **ARM64** architecture devices (such as Raspberry Pi, Orange Pi, etc.).

## 📊 Compatibility & Test Report

This image is built for ARM64 architecture. Due to differences in hardware and virtualization environments, some devices may require specific configurations.

| Device / Environment | Status | Notes & Configuration |
| :--- | :--- | :--- |
| **Orange Pi 5 Plus** | ✅ Passed | Works out of the box. No modifications needed. |
| **Raspberry Pi 5** | ⚠️ Passed | Kernel page size compatibility issue. **Configuration change required** (see solution below). |
| **Pixel (Android 16)** | ⚠️ Passed | **Env**: Built-in Linux Terminal in Developer Mode (AVF).<br>**Note**: Access is limited to localhost (`127.0.0.1`) by default. For LAN access, a tool like **Port Forwarder** is required. |
| **Android Termux** | ❌ Failed | `udocker` mode is not supported. |
| **Android Termux** | ⏳ Pending | QEMU software emulation mode is untested. |

### 🍓 Special Note for Raspberry Pi 5

If you encounter a `400 Bad Request` error on Raspberry Pi 5, please follow these steps:

1.  Edit the `/boot/firmware/config.txt` file on the host.
2.  Add the following line to the end of the file:
    ```ini
    kernel=kernel8.img
    ```
3.  **Reboot the Raspberry Pi** for changes to take effect.

---

## ⚠️ Other Limitations

*   **Architecture**: Only supports **ARM64**. x86/amd64 is not supported.
*   **Features**: Host **Disk Management** is not supported inside the container; only core backup/restore functions are available.

---

## 🚀 Quick Deployment

Before use, please ensure you have set the necessary environment variables, especially `ROOT_PASSWORD`.

### Option 1: Docker CLI

```bash
docker run -d \
  --name pbs \
  --restart unless-stopped \
  -p 8007:8007 \
  -e ROOT_PASSWORD="YourStrongPassword" \
  -e TZ="Asia/Shanghai" \
  -v /dockerData/pbs/lib:/var/lib/proxmox-backup \
  -v /dockerData/pbs/etc:/etc/proxmox-backup \
  -v /dockerData/pbs/datastore:/datastore \
  --tmpfs /run/proxmox-backup/shmem \
  souloh/pbs:arm64-latest
```

> **Note**: The `--tmpfs` parameter is crucial for PBS performance and stability; do not remove it.

### Option 2: Docker Compose (Recommended)

Create a `docker-compose.yml` file and add the following content:

```yaml
version: "3.8"

services:
  pbs:
    image: souloh/pbs:arm64-latest
    container_name: pbs
    restart: unless-stopped
    environment:
      # ⚠️ You must change this password
      ROOT_PASSWORD: "YourStrongPassword"
      TZ: "Asia/Shanghai"
    ports:
      - "8007:8007"
    volumes:
      - /dockerData/pbs/lib:/var/lib/proxmox-backup
      - /dockerData/pbs/etc:/etc/proxmox-backup
      - /dockerData/pbs/datastore:/datastore
    tmpfs:
      - /run/proxmox-backup/shmem
```

Start the container:

```bash
docker-compose up -d
```

---

## ⚙️ Initialization Configuration Guide

After the container starts, follow these steps to complete initialization:

1.  **Access the Web Interface**
    Open your browser and visit: `https://<Your-IP>:8007`
    *(Note: It uses the https protocol. The browser may warn about an insecure certificate; simply choose to proceed.)*

2.  **Login**
    *   **Username**: `root`
    *   **Password**: The password you set in the `ROOT_PASSWORD` environment variable.
    *   **Realm**: Select `Linux PAM standard authentication`.

3.  **Add Datastore**
    After logging in, click **Datastore** -> **Add Datastore** in the left menu:
    *   **Name**: Custom name (e.g., `backup-01`)
    *   **Backing Path**: Must be `/datastore`
        *(This is the path we mounted in Docker)*

After completing the above steps, you can start using PBS for backups.

---

## 🤝 Feedback & Contribution

If you successfully test this on other ARM64 devices, please submit an Issue or feedback to help others.