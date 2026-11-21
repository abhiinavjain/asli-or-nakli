FROM python:3.11-slim
WORKDIR /app
COPY phase3/app/requirements.txt .
# anthropic is optional in requirements.txt; installed here so the AI answer
# works whenever ANTHROPIC_API_KEY is set
RUN pip install --no-cache-dir -r requirements.txt anthropic
COPY phase3/ /phase3/
WORKDIR /phase3/app
EXPOSE 8501
CMD ["streamlit", "run", "gui.py", \
     "--server.address=0.0.0.0", "--server.port=8501", \
     "--server.headless=true", "--browser.gatherUsageStats=false"]
