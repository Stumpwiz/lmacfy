from flask import Flask, request, render_template_string
import openai
import os

app = Flask(__name__)

# Set up OpenAI API Key
openai.api_key = os.getenv("OPENAI_API_KEY")

TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <title>Let Me Ask ChatGPT For You</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <script>
        function typeEffect(text, elementId, speed) {
            let i = 0;
            function type() {
                if (i < text.length) {
                    document.getElementById(elementId).innerHTML += text.charAt(i);
                    i++;
                    setTimeout(type, speed);
                }
            }
            type();
        }

        function copyToClipboard() {
            let copyText = document.getElementById("share_url").href;
            navigator.clipboard.writeText(copyText);
            alert("Link copied to clipboard!");
        }

        function toggleDarkMode() {
            document.body.classList.toggle("bg-dark");
            document.body.classList.toggle("text-light");
        }

        function showLoading() {
            document.getElementById("loading").style.display = "block";
            document.getElementById("answer").innerHTML = "";
        }

        window.onload = function() {
            let answer = "{{ answer | safe }}";
            document.getElementById("loading").style.display = "none";
            typeEffect(answer, "answer", 50);
        };
    </script>
</head>
<body class="container mt-5">
    <div class="card p-4">
        <h1 class="mb-3">Let Me Ask ChatGPT For You</h1>
        <button class="btn btn-secondary mb-3" onclick="toggleDarkMode()">Toggle Dark Mode</button>
        <form method="GET" action="/" onsubmit="showLoading()">
            <div class="mb-3">
                <input type="text" class="form-control" name="q" placeholder="Ask a question..." required>
            </div>
            <button type="submit" class="btn btn-primary">Ask</button>
        </form>
        <p id="loading" style="display: none;" class="mt-3"><span class="spinner-border"></span> Generating answer...</p>
        <p><strong>Question:</strong> {{ question }}</p>
        <p><strong>Answer:</strong> <span id="answer"></span></p>
        <p>Share this: <a id="share_url" href="{{ share_url }}">{{ share_url }}</a>
           <button class="btn btn-sm btn-outline-secondary" onclick="copyToClipboard()">Copy Link</button></p>
    </div>
</body>
</html>
"""

def get_chatgpt_answer(question):
    client = openai.OpenAI()
    response = client.chat.completions.create(
        model="gpt-3.5-turbo",
        messages=[{"role": "system", "content": "You are a helpful assistant."},
                  {"role": "user", "content": question}]
    )
    return response.choices[0].message.content

@app.route('/')
def ask():
    question = request.args.get('q', 'What is AI?')
    answer = get_chatgpt_answer(question)
    share_url = request.host_url + '?q=' + question.replace(' ', '+')
    return render_template_string(TEMPLATE, question=question, answer=answer, share_url=share_url)

if __name__ == '__main__':
    app.run(debug=True)
