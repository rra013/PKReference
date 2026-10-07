# The PK Reference server, as an image: built from the repository root, since the server bundles
# the app's data files (the champions-*.json regulations, Showdown's data, Team Search's vocabulary).
#
#   docker build -f backend/Dockerfile -t pkref-api .
#
# docker-compose.server.yml builds and runs it on a server, beside Kafka and Postgres. The tests
# run on GitHub Actions, so the image build skips them.

FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /src
COPY backend/pom.xml backend/pom.xml
RUN mvn -f backend/pom.xml -B -q dependency:go-offline
COPY champions-*.json ./
COPY PKReference/showdown-champions-data.json PKReference/team_search_vocab.json PKReference/
COPY backend/src backend/src
RUN mvn -f backend/pom.xml -B -q -DskipTests package

FROM eclipse-temurin:21-jre
RUN useradd --system --no-create-home pkref
COPY --from=build /src/backend/target/pkreference-backend-*.jar /app/server.jar
USER pkref
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/server.jar"]
