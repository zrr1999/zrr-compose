import { pathToFileURL } from "node:url";
import net from "node:net";

const defaultHubEntry =
  "/opt/spark/node_modules/@zendev-lab/spark-hub/dist/spark-hub-server.js";
const loopbackHosts = new Set(["127.0.0.1", "::1", "localhost"]);

function parsePort(value, name) {
  const port = Number(value);
  if (!Number.isSafeInteger(port) || port < 1 || port > 65_535) {
    throw new Error(`${name} must be an integer between 1 and 65535.`);
  }
  return port;
}

export function createLoopbackProxy({ targetHost, targetPort }) {
  if (!loopbackHosts.has(targetHost)) {
    throw new Error(`Spark Hub proxy target must be loopback, received ${targetHost}.`);
  }

  const sockets = new Set();
  const track = (socket) => {
    sockets.add(socket);
    socket.once("close", () => sockets.delete(socket));
  };

  const server = net.createServer((client) => {
    const upstream = net.createConnection({ host: targetHost, port: targetPort });
    track(client);
    track(upstream);
    client.on("error", () => upstream.destroy());
    upstream.on("error", () => client.destroy());
    client.pipe(upstream);
    upstream.pipe(client);
  });

  return { server, sockets };
}

function listen(server, port) {
  return new Promise((resolve, reject) => {
    const onError = (error) => {
      server.off("listening", onListening);
      reject(error);
    };
    const onListening = () => {
      server.off("error", onError);
      resolve();
    };
    server.once("error", onError);
    server.once("listening", onListening);
    server.listen(port, "0.0.0.0");
  });
}

function stopProxy(server, sockets) {
  if (server.listening) server.close();
  for (const socket of sockets) socket.destroy();
}

export async function run(env = process.env) {
  const targetHost = env.HOST?.trim() || "127.0.0.1";
  const targetPort = parsePort(env.PORT?.trim() || "5174", "PORT");
  const proxyPort = parsePort(
    env.SPARK_HUB_CONTAINER_PROXY_PORT?.trim() || "5173",
    "SPARK_HUB_CONTAINER_PROXY_PORT",
  );
  if (targetPort === proxyPort) {
    throw new Error("Spark Hub and its container proxy must use different ports.");
  }

  const { server, sockets } = createLoopbackProxy({ targetHost, targetPort });
  await listen(server, proxyPort);
  console.log(
    `Spark Hub container proxy listening on 0.0.0.0:${proxyPort} -> ${targetHost}:${targetPort}`,
  );
  server.unref();

  const hubEntry = env.SPARK_HUB_SERVER_ENTRY?.trim() || defaultHubEntry;
  const onSigint = () => stopProxy(server, sockets);
  const onSigterm = () => stopProxy(server, sockets);
  process.once("SIGINT", onSigint);
  process.once("SIGTERM", onSigterm);

  try {
    await import(pathToFileURL(hubEntry).href);
  } catch (error) {
    stopProxy(server, sockets);
    throw error;
  }
}

const invokedPath = process.argv[1] ? pathToFileURL(process.argv[1]).href : null;
if (invokedPath === import.meta.url) {
  run().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}
