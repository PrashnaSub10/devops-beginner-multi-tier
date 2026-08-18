FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py ./
# python:slim ships a non-root "nobody" user we can reuse
USER nobody
EXPOSE 8080
CMD ["python", "app.py"]
