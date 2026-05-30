"""
RAG pipeline на базе LangChain + ChromaDB + Ollama (Llama 3.1 8B).

Векторная база содержит:
  - Нормативы ЦБ РФ по ПДН
  - Справочник категорий трат
  - Советы по личным финансам
  - Информацию о банковских продуктах
"""

from langchain_ollama import OllamaLLM
from langchain_community.vectorstores import Chroma
from langchain_community.embeddings import OllamaEmbeddings
from langchain.chains import RetrievalQA
from langchain.prompts import PromptTemplate

from app.config import settings

SYSTEM_PROMPT = """Ты — финансовый помощник. Отвечай только на русском языке.
Используй предоставленный контекст для ответа. Если информации нет в контексте — скажи об этом честно.
Не придумывай цифры и ставки. Будь краток и конкретен.

Контекст:
{context}

Вопрос: {question}
Ответ:"""

_qa_chain = None


def get_qa_chain() -> RetrievalQA:
    global _qa_chain
    if _qa_chain is not None:
        return _qa_chain

    embeddings = OllamaEmbeddings(
        model=settings.ollama_model,
        base_url=settings.ollama_base_url,
    )

    vectorstore = Chroma(
        collection_name=settings.chroma_collection_finance,
        embedding_function=embeddings,
        client_settings={
            "chroma_server_host": settings.chroma_host,
            "chroma_server_http_port": settings.chroma_port,
        },
    )

    llm = OllamaLLM(
        model=settings.ollama_model,
        base_url=settings.ollama_base_url,
        timeout=settings.ollama_timeout,
    )

    prompt = PromptTemplate(template=SYSTEM_PROMPT, input_variables=["context", "question"])

    _qa_chain = RetrievalQA.from_chain_type(
        llm=llm,
        retriever=vectorstore.as_retriever(search_kwargs={"k": 4}),
        chain_type_kwargs={"prompt": prompt},
        return_source_documents=False,
    )
    return _qa_chain


async def ask(question: str) -> str:
    chain = get_qa_chain()
    result = chain.invoke({"query": question})
    return result.get("result", "").strip()
