import { fal } from "@fal-ai/client";

const MODEL = "fal-ai/hunyuan-3d/v3.1/pro/image-to-3d";

function configureFal() {
  const key = process.env.FAL_KEY;
  if (!key) {
    throw new Error("FAL_KEY is not configured on the generation server.");
  }
  fal.config({ credentials: key });
}

function json(res, status, body) {
  res.status(status).setHeader("Content-Type", "application/json");
  res.setHeader("Cache-Control", "no-store");
  res.end(JSON.stringify(body));
}

function bodyObject(req) {
  if (typeof req.body === "string") {
    return JSON.parse(req.body);
  }
  return req.body ?? {};
}

export default async function handler(req, res) {
  try {
    configureFal();

    if (req.method === "POST") {
      const body = bodyObject(req);
      const imageDataURI = body.imageDataURI;

      if (
        typeof imageDataURI !== "string" ||
        !imageDataURI.startsWith("data:image/")
      ) {
        return json(res, 400, { error: "imageDataURI is required." });
      }

      const submitted = await fal.queue.submit(MODEL, {
        input: {
          input_image_url: imageDataURI,
          generate_type: "Normal",
          enable_pbr: true,
          face_count: 1000000
        }
      });

      return json(res, 202, {
        id: submitted.request_id,
        status: "queued"
      });
    }

    if (req.method === "GET") {
      const id = Array.isArray(req.query?.id) ? req.query.id[0] : req.query?.id;
      if (!id) {
        return json(res, 400, { error: "id is required." });
      }

      const status = await fal.queue.status(MODEL, {
        requestId: id,
        logs: false
      });

      if (status.status === "COMPLETED") {
        const result = await fal.queue.result(MODEL, { requestId: id });
        const data = result.data ?? result;
        const urls = data.model_urls ?? {};

        return json(res, 200, {
          status: "completed",
          thumbnailURL: data.thumbnail?.url ?? null,
          glbURL: urls.glb?.url ?? data.model_glb?.url ?? null,
          usdzURL: urls.usdz?.url ?? null
        });
      }

      if (status.status === "FAILED") {
        return json(res, 200, {
          status: "failed",
          error: "The 3D provider reported a failed generation."
        });
      }

      return json(res, 200, {
        status: status.status === "IN_QUEUE" ? "queued" : "running"
      });
    }

    res.setHeader("Allow", "GET, POST");
    return json(res, 405, { error: "Method not allowed." });
  } catch (error) {
    return json(res, 500, {
      error: error instanceof Error ? error.message : "Generation server error."
    });
  }
}
