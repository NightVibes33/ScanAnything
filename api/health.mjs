export default function handler(_req, res) {
  res.status(200).json({
    ok: true,
    providerConfigured: Boolean(process.env.FAL_KEY)
  });
}
