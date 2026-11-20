#!/usr/bin/env python3
"""Pre-compute SigLIP text embeddings for CheStoria content.

The app ships only SigLIP's image encoder (Core ML). Text never changes on the device, so the
text side is computed here once: every place's `aiDescriptions` and every label in ai/labels.json.
Run this after adding a place, editing a description or changing the label list:

  pip install torch transformers sentencepiece
  python3 tools/embed_content.py            # writes CheStoria/Resources/Content/ai/text-embeddings.json

Model: google/siglip-base-patch16-224 (Apache-2.0). Embeddings are L2-normalised float16, base64.
"""
import base64, json, os, sys
import numpy as np

CONTENT = os.path.join(os.path.dirname(__file__), "..", "CheStoria", "Resources", "Content")


def main():
    import torch
    from transformers import SiglipModel, SiglipTokenizer
    catalog = json.load(open(os.path.join(CONTENT, "catalog.json"), encoding="utf-8"))
    model_id = catalog["ai"]["model"]
    model = SiglipModel.from_pretrained(model_id).eval()
    tok = SiglipTokenizer.from_pretrained(model_id)

    def embed(texts):
        batch = tok(texts, padding="max_length", max_length=64, truncation=True, return_tensors="pt")
        with torch.no_grad():
            f = model.get_text_features(**batch)
        f = f / f.norm(dim=-1, keepdim=True)
        return [base64.b64encode(v.numpy().astype("<f2").tobytes()).decode() for v in f]

    labels = json.load(open(os.path.join(CONTENT, catalog["ai"]["labels"]), encoding="utf-8"))["labels"]
    out = {"model": model_id, "dimension": int(model.config.text_config.hidden_size),
           "logitScale": float(model.logit_scale.exp()), "logitBias": float(model.logit_bias),
           "labels": dict(zip([l["id"] for l in labels], embed([l["prompt"] for l in labels]))), "places": {}}
    for entry in catalog["sites"]:
        site = json.load(open(os.path.join(CONTENT, entry["file"]), encoding="utf-8"))
        for p in site["places"]:
            if p.get("aiDescriptions"):
                out["places"][p["id"]] = embed([f"a photo of {d}" for d in p["aiDescriptions"]])
    path = os.path.join(CONTENT, catalog["ai"]["textEmbeddings"])
    json.dump(out, open(path, "w"), indent=1)
    print(f"wrote {path}: {len(out['labels'])} labels, {len(out['places'])} places")


if __name__ == "__main__":
    sys.exit(main())
