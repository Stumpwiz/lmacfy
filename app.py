from flask import Flask, request, render_template
import openai
import os
import logging
from urllib.parse import urlencode
from dotenv import load_dotenv

# Load environment variables from the .env file (for local development)
load_dotenv()

app = Flask(__name__)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Validate and set up OpenAI API Key
api_key = os.getenv("OPENAI_API_KEY")
if not api_key:
    logger.error("OPENAI_API_KEY environment variable is not set!")
    raise ValueError("OPENAI_API_KEY environment variable is required. Please set it in your environment or .env file.")

openai.api_key = api_key

# Configure model (default to gpt-4o-mini)
OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
logger.info(f"Using OpenAI model: {OPENAI_MODEL}")


def get_chatgpt_answer(question: str) -> str:
    """
    Query OpenAI's GPT-4o-mini model with error handling.

    Args:
        question: The user's question string

    Returns:
        str: The AI-generated answer

    Raises:
        Exception: Re-raises exceptions after logging for the caller to handle
    """
    try:
        logger.info(f"Querying OpenAI API for question: {question[:50]}...")
        client = openai.OpenAI()

        response = client.chat.completions.create(
            model=OPENAI_MODEL,
            messages=[  # type: ignore[arg-type]
                {"role": "system", "content": "You are a helpful assistant."},
                {"role": "user", "content": question}
            ],
            max_tokens=500,  # Limit response length for cost control
            temperature=0.7
        )
        answer = response.choices[0].message.content
        logger.info("Successfully received answer from OpenAI API")
        return answer
    except openai.RateLimitError as e:
        logger.error(f"OpenAI rate limit exceeded: {e}")
        raise Exception("API rate limit exceeded. Please try again later.")
    except openai.AuthenticationError as e:
        logger.error(f"OpenAI authentication failed: {e}")
        raise Exception("API authentication failed. Please check your API key.")
    except openai.APIConnectionError as e:
        logger.error(f"OpenAI API connection error: {e}")
        raise Exception("Unable to connect to OpenAI API. Please check your internet connection.")
    except Exception as e:
        logger.error(f"Unexpected error calling OpenAI API: {e}")
        raise Exception("An unexpected error occurred. Please try again.")


@app.route('/')
def ask():
    """
    Main route handler for the application.
    Accepts a question via query parameter 'q' or 'ref' (for copilot.microsoft.com compatibility)
    and returns an AI-generated answer.
    """
    # Support both 'q' and 'ref' parameters for copilot.microsoft.com compatibility
    # 'ref' parameter is URL-encoded question from copilot.microsoft.com
    question = request.args.get('q') or request.args.get('ref', '')

    # If no question provided, show the form without any answer
    if not question:
        return render_template('index.html', question=None, answer=None, error=None)

    try:
        # Get answer from ChatGPT
        answer = get_chatgpt_answer(question)

        # Create a properly encoded share URL
        query_params = urlencode({'q': question})
        share_url = f"{request.host_url}?{query_params}"

        return render_template(
            'index.html',
            question=question,
            answer=answer,
            share_url=share_url,
            error=None
        )
    except Exception as e:
        logger.error(f"Error processing request: {e}")
        # Return an error page with a user-friendly message
        return render_template(
            'index.html',
            question=question,
            answer=None,
            share_url=None,
            error=str(e)
        )


if __name__ == '__main__':
    port = int(os.environ.get("PORT", 5000))
    logger.info(f"Starting Flask app on port {port}")
    app.run(host="0.0.0.0", port=port, debug=False)

