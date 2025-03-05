FROM node:alpine
ENV AWS_SECRET_KEY=123123123123
WORKDIR /usr/src/app
COPY package*.json ./
RUN npm install
RUN npm audit

COPY . .
EXPOSE 3000 22
USER root
HEALTHCHECK CMD curl --fail http://localhost:3000 || exit 1
CMD ["node","app.js"]