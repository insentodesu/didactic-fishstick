# Stage 1: сборка Flutter web
FROM ghcr.io/cirruslabs/flutter:stable AS builder

WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .

# --no-web-resources-cdn: бандлим CanvasKit локально (иначе тянется с gstatic.com,
#   что в РФ медленно/блокируется — главная причина долгой первой загрузки).
# --pwa-strategy=offline-first: SW кеширует ассеты, вторая загрузка мгновенная.
RUN flutter build web --release --no-web-resources-cdn --pwa-strategy=offline-first

# Stage 2: раздача через nginx
FROM nginx:1.27-alpine

COPY --from=builder /app/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
