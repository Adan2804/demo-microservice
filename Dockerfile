FROM node:18-alpine

WORKDIR /app

# Copiar package.json
COPY package*.json ./

# Instalar dependencias
RUN npm install

# Copiar código fuente
COPY . .

# Exponer puerto
EXPOSE 3000

# Build arguments
ARG NODE_ENV=production
ARG APP_VERSION=stable-v1.0.0
ARG EXPERIMENT_ENABLED=false

# Variables de entorno usando build args
ENV NODE_ENV=${NODE_ENV}
ENV APP_VERSION=${APP_VERSION}
ENV EXPERIMENT_ENABLED=${EXPERIMENT_ENABLED}

# Comando de inicio
CMD ["npm", "start"]