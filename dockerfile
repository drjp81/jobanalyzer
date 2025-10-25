# image is compatible ARM/64 and AMD 64
FROM drjp81/powershell:latest

# System deps
RUN apt-get update && apt-get install -y --no-install-recommends python3 python3-pip && rm -rf /var/lib/apt/lists/*


# App setup
RUN mkdir /app
WORKDIR /app
COPY ./requirements.txt /app/requirements.txt
RUN pip3 install --break-system-packages -r /app/requirements.txt

# Copy scripts
COPY collector/collector.py /app/collector.py
COPY /powershell_scripts/* /app/

# Data volume
VOLUME ["/DATA"]

# Default environment
ENV DATA_DIR=/DATA

# Entrypoint: run the collector once
CMD ["pwsh", "-file", "/app/flow.ps1"]
