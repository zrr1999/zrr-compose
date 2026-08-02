ARG SPARK_IMAGE=ghcr.io/zendev-lab/spark:0.2.0
FROM ${SPARK_IMAGE}

USER root

# Spark 0.2.0 ships migrations beside dist/, while the bundled server resolves
# them beside its compiled chunk. Keep one copy and bridge the packaged path.
RUN migrations=/opt/spark/node_modules/@zendev-lab/spark/dist/migrations \
    && target=/opt/spark/node_modules/@zendev-lab/spark/build/server/chunks/chunks/migrations \
    && test -d "${migrations}" \
    && mkdir -p "$(dirname "${target}")" \
    && ln -s "${migrations}" "${target}"

USER node
