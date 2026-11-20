# SigLIPVision.mlpackage

Image encoder of **google/siglip-base-patch16-224** (https://huggingface.co/google/siglip-base-patch16-224),
by Google, licensed under the Apache License 2.0 (see LICENSE-SigLIP-Apache-2.0.txt).

Modifications: the vision tower only, converted to Core ML with coremltools 8.1, outputs L2-normalised
768-d embeddings, weights palettised to 6 bits (cosine similarity ≥ 0.985 vs the original PyTorch model).
Text embeddings for content are produced offline by tools/embed_content.py with the same model.
