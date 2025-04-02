# Use a lightweight Python image
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Copy requirements and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the exporter script
COPY webhook.py .

# Expose Prometheus metrics port
EXPOSE 443

# Run the exporter
CMD ["python", "./webhook.py"]