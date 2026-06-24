FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    # OCR
    tesseract-ocr \
    tesseract-ocr-fra \
    # HEIC/HEIF photo support (pillow-heif build deps)
    libheif-dev \
    cmake \
    # asyncpg C extension
    gcc \
    g++ \
    libpq-dev \
    # cryptography / cffi build deps
    libffi-dev \
    libssl-dev \
    # Pillow image libs (used by pytesseract + pillow-heif)
    libjpeg-dev \
    zlib1g-dev \
    libpng-dev \
    libfreetype6-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000
CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT:-8000}"]
