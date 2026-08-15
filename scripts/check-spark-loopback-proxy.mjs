import assert from "node:assert/strict";
import net from "node:net";
import { once } from "node:events";
import { createLoopbackProxy } from "../deployments/home/home-control/configs/spark/loopback-proxy.mjs";

async function listen(server) {
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  return server.address().port;
}

async function close(server) {
  if (!server.listening) return;
  server.close();
  await once(server, "close");
}

const upstream = net.createServer((socket) => socket.pipe(socket));
const upstreamPort = await listen(upstream);
const { server: proxy, sockets } = createLoopbackProxy({
  targetHost: "127.0.0.1",
  targetPort: upstreamPort,
});
const proxyPort = await listen(proxy);

try {
  const client = net.createConnection({ host: "127.0.0.1", port: proxyPort });
  await once(client, "connect");
  client.write("spark-loopback-proxy");
  const [response] = await once(client, "data");
  assert.equal(response.toString("utf8"), "spark-loopback-proxy");
  client.end();
  assert.throws(
    () => createLoopbackProxy({ targetHost: "0.0.0.0", targetPort: upstreamPort }),
    /must be loopback/u,
  );
} finally {
  for (const socket of sockets) socket.destroy();
  await close(proxy);
  await close(upstream);
}

console.log("spark loopback proxy: forwarding and target isolation are valid");
