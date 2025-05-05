## 🧰 FULL BEGINNER GUIDE: IB Gateway + TradeUI (Docker-only Setup)

---

### 📦 What You'll Achieve

You’ll run everything in Docker:

* 🐳 `ib-gateway`: for live or paper trading
* 🐳 `trade`: the CLI from [TradeUI](https://github.com/TradeWithIt/TradeUI)
* 📁 Mount your `.so` strategy file
* ⚡ Execute it against live contracts

---

## 🪜 STEP-BY-STEP INSTRUCTIONS

---

### ✅ 1. Clone the TradeUI repo (with Dockerfile)

```bash
git clone https://github.com/TradeWithIt/TradeUI.git
cd TradeUI
```

---

### ✅ 2. Build the TradeUI Docker image

```bash
docker build -t trade-cli .
```

This uses the Dockerfile already provided in the repo.

---

### ✅ 3. Prepare Your Strategy `.so` File

Make sure your compiled `.so` file is in the same directory (or full path):

```bash
ls
# Should include: MyStrategy.so
```

---

### ✅ 4. Run the CLI with your strategy

```bash
docker run --rm \
  -v $(pwd)/MyStrategy.so:/strategy.so \
  trade-cli /strategy.so FUT ESM5 60 CME USD
```

> Replace `MyStrategy.so` with the path to your `.so` file

---

### ✅ 5. Set up IB Gateway in a separate folder

Create a folder:

```bash
mkdir ../ib-gateway-setup && cd ../ib-gateway-setup
```

Create `.env`:

```env
TWSUSERID=your_username
TWSPASSWORD=your_password
```

Create `docker-compose.yml`:

```yaml
version: "3.8"

services:
  ib-gateway:
    image: gnzsnz/ib-gateway:latest
    container_name: ib-gateway
    environment:
      TWSUSERID: "${TWSUSERID}"
      TWSPASSWORD: "${TWSPASSWORD}"
      TRADINGMODE: "live"
      READONLY: "false"
    ports:
      - "4001:4001"
      - "4002:4002"
    volumes:
      - ./config:/root/ibcontroller/config
    restart: unless-stopped
```

Create a config file:

```bash
mkdir config && touch config/ibgateway.config.ini
```

With contents:

```ini
[Logon]
ReadOnly=No
TradingMode=live
UseSSL=Yes
```

---

### ✅ 6. Run the IB Gateway

```bash
docker compose up -d
```

The gateway will start on port `4002`.

---

### ✅ 7. Connect Your TradeUI CLI to the Gateway

The TradeUI CLI will auto-connect to IB Gateway on port `4002` if the strategy is configured to do so.

---

## ✅ Summary

| Step | Component                     | Notes              |
| ---- | ----------------------------- | ------------------ |
| 1    | `docker build -t trade-cli .` | From TradeUI repo  |
| 2    | `docker run ... trade-cli`    | Run CLI with `.so` |
| 3    | `docker compose up`           | Run IB Gateway     |
| 4    | Port 4002                     | Exposes API to CLI |

---
