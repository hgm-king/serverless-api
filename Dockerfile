FROM node:16-alpine AS appbuild
WORKDIR /usr/src/app
COPY package.json ./
RUN npm install
COPY ./src ./src


FROM node:16-alpine
WORKDIR /usr/src/app
COPY --from=appbuild /usr/src/app ./
COPY ./.env ./.env
CMD npm start