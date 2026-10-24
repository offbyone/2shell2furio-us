import shlex
import webbrowser

from invoke.main import program
from invoke.tasks import task
from livereload import Server
from pelican import main as pelican_main
from pelican.settings import DEFAULT_CONFIG, get_settings_from_file

SETTINGS_FILE = "pelicanconf.py"
SETTINGS = {**DEFAULT_CONFIG, **get_settings_from_file(SETTINGS_FILE)}
HOST = "localhost"
PORT = 8000


def pelican_run(arguments: str) -> None:
    command = f"{arguments} {program.core.remainder}"
    pelican_main(shlex.split(command))


@task
def livereload(_context) -> None:
    """Build and serve the site, rebuilding when source files change."""

    def build() -> None:
        pelican_run(f"-s {SETTINGS_FILE} --fatal=errors -o output content")

    build()
    server = Server()
    for pattern in (
        SETTINGS_FILE,
        "publishconf.py",
        "content/**/*.md",
        "themes/2shell/templates/**/*.html",
        "themes/2shell/static/**/*.css",
    ):
        server.watch(pattern, build)

    webbrowser.open(f"http://{HOST}:{PORT}")
    server.serve(host=HOST, port=PORT, root=SETTINGS["OUTPUT_PATH"])
