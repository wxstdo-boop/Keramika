"""Colab-скрипт обучения новой Ады на Gemma-совместимой базе.

Запускать в Google Colab с GPU. Сначала загрузите рядом файл
`ada_gemma_train.jsonl`, затем выполните ячейки по порядку.

Важно: это новая LoRA на базе Gemma, а не точная копия прежней Qwen-LoRA,
потому что исходный датасет старого обучения отсутствует.
"""
# CELL 1: install
# !pip -q install -U transformers datasets peft accelerate bitsandbytes trl

# CELL 2: imports and config
import os
import torch
from datasets import load_dataset
from transformers import AutoTokenizer, AutoModelForCausalLM, BitsAndBytesConfig
from peft import LoraConfig
from trl import SFTTrainer, SFTConfig

BASE = "google/gemma-2-2b-it"
OUT = "/content/ada-gemma-lora"
DATA = "/content/ada_gemma_train.jsonl"

# Upload data/ada_gemma_train.jsonl through Colab's Files panel first.
dataset = load_dataset("json", data_files=DATA, split="train")

def format_row(row):
    return {
        "text": "\n".join(
            f"<{m['role']}>\n{m['content']}\n</{m['role']}>"
            for m in row["messages"]
        )
    }
dataset = dataset.map(format_row)

bnb = BitsAndBytesConfig(
    load_in_4bit=True,
    bnb_4bit_quant_type="nf4",
    bnb_4bit_compute_dtype=torch.float16,
)
tokenizer = AutoTokenizer.from_pretrained(BASE)
model = AutoModelForCausalLM.from_pretrained(
    BASE,
    quantization_config=bnb,
    device_map="auto",
)

lora = LoraConfig(
    r=32,
    lora_alpha=64,
    lora_dropout=0.05,
    target_modules=["q_proj", "k_proj", "v_proj", "o_proj", "gate_proj", "up_proj", "down_proj"],
    task_type="CAUSAL_LM",
)

args = SFTConfig(
    output_dir=OUT,
    dataset_text_field="text",
    max_seq_length=1024,
    num_train_epochs=5,
    per_device_train_batch_size=2,
    gradient_accumulation_steps=4,
    learning_rate=2e-4,
    logging_steps=1,
    save_strategy="no",
    report_to="none",
    fp16=True,
)
trainer = SFTTrainer(
    model=model,
    tokenizer=tokenizer,
    train_dataset=dataset,
    peft_config=lora,
    args=args,
)
trainer.train()
trainer.save_model(OUT)
tokenizer.save_pretrained(OUT)
print("Готово:", OUT)

# CELL 3: package adapter for Cloudflare upload
# !tar -czf /content/ada-gemma-lora.tar.gz -C /content ada-gemma-lora
# from google.colab import files
# files.download('/content/ada-gemma-lora.tar.gz')

# CELL 4: quick local smoke test
# prompt = "<system>\nТы Ада — тёплая и умная девушка.\n</system>\n<user>\nПривет!\n</user>\n<assistant>\n"
# inputs = tokenizer(prompt, return_tensors="pt").to(model.device)
# with torch.inference_mode():
#     out = model.generate(**inputs, max_new_tokens=80, temperature=0.8, do_sample=True)
# print(tokenizer.decode(out[0], skip_special_tokens=True))
