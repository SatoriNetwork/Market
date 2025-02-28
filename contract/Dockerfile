FROM node:20-slim

# Install required packages
RUN apt-get update && \
    apt-get install -y python3 make g++ git && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install -g truffle
RUN npm install

# Copy project files
COPY . .