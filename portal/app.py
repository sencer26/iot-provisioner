from flask import Flask, request, render_template
import credentials

app = Flask(__name__)

@app.route('/', methods=['GET', 'POST'])
def index():
    if request.method == 'POST':
        ssid = request.form['ssid']
        password = request.form['password']
        credentials.write_credentials(ssid, password)
        return "Connecting... Please wait 1 minute and reconnect."
    return render_template('index.html')

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80)
