# 操作ログの解析を Docker で動かす(Python のインストール不要)。仕様: docs/logging.md 第8章
#   ビルド: docker build -t claude-hotkey-analyze analysis
#   実行:   docker run --rm -v "<ログフォルダ>:/logs:ro" claude-hotkey-analyze
#   テスト: docker run --rm --entrypoint python claude-hotkey-analyze test_analyze.py
# Windows では analysis\analyze.ps1 がこれらをまとめて行う
FROM python:3.12-slim
ENV PYTHONUTF8=1 PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY analyze.py test_analyze.py ./
ENTRYPOINT ["python", "analyze.py"]
CMD ["/logs"]
