FROM python:3.11-slim

# tesseract-ocr: receipt OCR (pytesseract)
# tesseract-ocr-fra: French language pack (Cameroon)
# libheif-dev: HEIC/HEIF photo support (pillow-heif)
# gcc + libpq-dev: asyncpg C extension
RUN apt-get update && apt-get install -y --no-install-recommends \
    tesseract-ocr \
    tesseract-ocr-fra \
    libheif-dev \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000
CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT:-8000}"]
