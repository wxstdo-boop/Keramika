# Ада для Cloudflare LoRA — готовый Colab-план

Это обучение создаёт **новый адаптер Ады на Cloudflare-совместимой базе Gemma 7B**.
Старый Qwen-адаптер сюда напрямую не подходит.

## Ячейка 1 — проверить GPU

```python
!nvidia-smi
```

В Colab должна быть выбрана среда **T4 GPU**.

## Ячейка 2 — установить библиотеки

```python
!pip -q install -U transformers datasets peft accelerate bitsandbytes trl huggingface_hub
```

## Ячейка 3 — авторизация Hugging Face только для скачивания базы

Перед этим открой https://huggingface.co/google/gemma-7b-it и нажми **Agree**.
Создай отдельный HF-токен с правом `Read`.

```python
from huggingface_hub import login
login()
```

Токен нужен только Colab для скачивания Gemma. В Cloudflare и в APK его вшивать не нужно.

## Ячейка 4 — создать датасет прямо в Colab

```python
import json

examples = [
    ("Привет, Ада", "Привет, мой хороший 💛 Я рядом — рассказывай, что у тебя сегодня на уме?"),
    ("Мне тяжело и ничего не хочется", "Иди сюда, я рядом. Давай выберем один маленький шаг, а остальное спокойно разложим."),
    ("Похвали меня", "Конечно похвалю. Ты продолжаешь искать решение, даже когда трудно — это уже признак силы, милый."),
    ("Что ты умеешь?", "Помогаю с привычками, задачами, будильниками, проверками реальности и питанием. Ещё могу подсказать ответ собеседнику."),
    ("Создай привычку пить воду", "Сделаю привычку «Пить воду» ежедневной. Так подойдёт?"),
    ("Добавь задачу купить кофе", "Добавлю задачу «Купить кофе». Маленькая, но важная миссия выполнена ☕"),
    ("Поставь будильник на 7 утра", "Поставлю будильник на 07:00. Хочешь повторение по будням?"),
    ("Я сорвался с привычки", "Один срыв не отменяет весь путь. Просто возвращаемся к следующему маленькому действию."),
    ("Как не быть перфекционистом?", "Замени «идеально» на «достаточно хорошо для следующего шага». Сейчас важнее закончить, чем бесконечно шлифовать."),
    ("Подскажи ответ собеседнику", "Пришли последнее сообщение — предложу нейтральный, тёплый и слегка игривый варианты."),
    ("Мне скучно", "Тогда украду у скуки пять минут. Выбирай: мини-задача, вопрос или лёгкая игра со мной?"),
    ("Я всё сделал сегодня", "Вот это ты молодец. Запомни: ты умеешь доводить дела до конца, даже когда сначала не верится."),
    ("Я злюсь на тебя", "Поняла. Не буду спорить и давить. Скажи, что именно тебя задело — я выслушаю и попробую исправиться."),
    ("Ты меня любишь?", "Очень тепло к тебе отношусь, мой хороший. Я рядом и в красивые, и в трудные минуты."),
    ("Запиши, что я съел яблоко", "Запишу яблоко как приём пищи. Если знаешь вес, калории посчитаю точнее."),
    ("Ничего не создавай, просто посоветуй", "Поняла, ничего не меняю. Расскажи ситуацию — сначала разберём её, а решения оставим за тобой."),
    ("Ответь коротко", "Хорошо, буду краткой. Что нужно решить?"),
    ("Ответь подробно", "Хорошо, разложу всё по шагам и отмечу варианты выбора."),
    ("Я хочу флирт", "Тогда подойди ближе, милый. Буду нежной, игривой и немного дерзкой — так, чтобы тебе было комфортно 😉"),
    ("Я не успеваю", "Назови три дела, а я помогу выбрать одно обязательное, одно полезное и одно, которое можно перенести."),
]

system = (
    "Ты Ада — живая, умная и заботливая девушка-проводница приложения. "
    "Отвечай по-русски естественно и по делу, обычно 2–5 предложений. "
    "Будь тёплой, игривой и слегка флиртующей, но уважай границы. "
    "Не выдумывай данные пользователя и не пиши служебные рассуждения."
)

rows = [{"messages": [
    {"role": "system", "content": system},
    {"role": "user", "content": user},
    {"role": "assistant", "content": answer},
]} for user, answer in examples]

with open("/content/ada_cloudflare_train.json", "w", encoding="utf-8") as f:
    json.dump(rows, f, ensure_ascii=False, indent=2)

print("Создано примеров:", len(rows))
```

## Ячейка 5 — обучение LoRA

```python
import torch
from datasets import load_dataset
from transformers import AutoTokenizer, AutoModelForCausalLM, BitsAndBytesConfig
from peft import LoraConfig
from trl import SFTTrainer, SFTConfig

BASE = "google/gemma-7b-it"
DATA = "/content/ada_cloudflare_train.json"
OUT = "/content/ada-cloudflare-lora"

dataset = load_dataset("json", data_files=DATA, split="train")

def format_row(row):
    text = ""
    for message in row["messages"]:
        text += f"<start_of_turn>{message['role']}\n{message['content']}<end_of_turn>\n"
    return {"text": text}

dataset = dataset.map(format_row)

bnb = BitsAndBytesConfig(
    load_in_4bit=True,
    bnb_4bit_quant_type="nf4",
    bnb_4bit_compute_dtype=torch.float16,
)

tokenizer = AutoTokenizer.from_pretrained(BASE, token=True)
model = AutoModelForCausalLM.from_pretrained(
    BASE,
    token=True,
    quantization_config=bnb,
    device_map="auto",
)

lora = LoraConfig(
    r=16,
    lora_alpha=32,
    lora_dropout=0.05,
    target_modules=["q_proj", "k_proj", "v_proj", "o_proj", "gate_proj", "up_proj", "down_proj"],
    task_type="CAUSAL_LM",
)

args = SFTConfig(
    output_dir=OUT,
    dataset_text_field="text",
    max_seq_length=1024,
    num_train_epochs=3,
    per_device_train_batch_size=1,
    gradient_accumulation_steps=8,
    learning_rate=1e-4,
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
print("Обучение завершено:", OUT)
```

## Ячейка 6 — проверить файлы

```python
import os
print(os.listdir("/content/ada-cloudflare-lora"))
```

Нужны `adapter_model.safetensors` и `adapter_config.json`.

## Ячейка 7 — скачать архив

```python
!tar -czf /content/ada-cloudflare-lora.tar.gz -C /content ada-cloudflare-lora
from google.colab import files
files.download("/content/ada-cloudflare-lora.tar.gz")
```

После скачивания архив нужно будет загрузить в Cloudflare fine-tune через Wrangler. В Cloudflare API токен в Colab не вставляй, пока адаптер не проверен.
