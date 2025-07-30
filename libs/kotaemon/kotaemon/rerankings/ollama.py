from __future__ import annotations

import json
from typing import Optional

import requests

from kotaemon.base import Document, Param

from .base import BaseReranking


class OllamaReranking(BaseReranking):
    """Ollama Reranking model using OpenAI-compatible API
    
    This class provides reranking functionality using Ollama's OpenAI-compatible API.
    It works by using a language model to score the relevance of documents to a query.
    """

    base_url: str = Param(
        "http://localhost:11434/v1/",
        help="Base Ollama URL with OpenAI-compatible endpoint",
        required=True,
    )
    model: str = Param(
        "qwen2.5:7b",
        help="Model name to use for reranking (https://ollama.com/library)",
        required=True,
    )
    api_key: str = Param(
        "ollama",
        help="API key for Ollama (can be any string for local Ollama)",
        required=True,
    )
    max_tokens: Optional[int] = Param(
        512,
        help="Maximum number of tokens for input text truncation",
    )
    temperature: float = Param(
        0.0,
        help="Temperature for model inference (0.0 for deterministic results)",
    )
    timeout: int = Param(
        30,
        help="Request timeout in seconds",
    )

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.session = requests.Session()
        self.session.headers.update({
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        })

    def _truncate_text(self, text: str) -> str:
        """Truncate text to max_tokens if specified"""
        if self.max_tokens and len(text) > self.max_tokens:
            return text[:self.max_tokens]
        return text

    def _score_relevance(self, query: str, document: str) -> float:
        """Score the relevance of a document to a query using Ollama model"""
        
        # Create a prompt for relevance scoring
        prompt = f"""Given the following query and document, rate the relevance of the document to the query on a scale from 0.0 to 1.0, where 0.0 means completely irrelevant and 1.0 means perfectly relevant.

Query: {query}

Document: {document}

Please respond with only a single number between 0.0 and 1.0 representing the relevance score."""

        payload = {
            "model": self.model,
            "messages": [
                {
                    "role": "user",
                    "content": prompt
                }
            ],
            "temperature": self.temperature,
            "max_tokens": 10,  # We only need a short numeric response
        }

        try:
            response = self.session.post(
                f"{self.base_url.rstrip('/')}/chat/completions",
                json=payload,
                timeout=self.timeout
            )
            response.raise_for_status()
            
            result = response.json()
            content = result["choices"][0]["message"]["content"].strip()
            
            # Extract numeric score from response
            try:
                score = float(content)
                # Ensure score is between 0.0 and 1.0
                return max(0.0, min(1.0, score))
            except ValueError:
                # If we can't parse the score, try to extract a number
                import re
                numbers = re.findall(r'0?\.\d+|[01]\.?\d*', content)
                if numbers:
                    score = float(numbers[0])
                    return max(0.0, min(1.0, score))
                else:
                    # Default to 0.5 if we can't parse
                    return 0.5
                    
        except Exception as e:
            print(f"Error scoring relevance with Ollama: {e}")
            # Return default score on error
            return 0.5

    def run(self, query: str, documents: list[Document]) -> list[Document]:
        """Rerank documents based on their relevance to the query"""
        if not documents:
            return documents

        # Score each document
        scored_docs = []
        for doc in documents:
            # Truncate document text if needed
            doc_text = self._truncate_text(doc.text)
            
            # Get relevance score
            score = self._score_relevance(query, doc_text)
            
            # Create new document with score
            scored_doc = Document(
                text=doc.text,
                metadata={
                    **(doc.metadata or {}),
                    "rerank_score": score,
                }
            )
            scored_docs.append((score, scored_doc))

        # Sort by score (descending)
        scored_docs.sort(key=lambda x: x[0], reverse=True)
        
        # Return sorted documents
        return [doc for _, doc in scored_docs]

    def __repr__(self):
        return f"OllamaReranking(base_url='{self.base_url}', model='{self.model}')"
