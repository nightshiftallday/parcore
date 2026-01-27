import subprocess
import os
from typing import Tuple
class ProcessRunner():

    #
    # Private methods (helping the public methods)
    #

    def _get_env(self):
        env = os.environ.copy()
        env["TERM"] = "xterm"
        return env

    def analyze_file_with_verible(self, file_path) -> Tuple[bool, str, str]:
        """
        Returns a tuple of (run_successfully, output, err_output)
        """
        result = subprocess.run(
            [
                "./tools/ila_generator/verible-verilog-syntax",
                "--export_json",
                "--printrawtokens",
                file_path
            ],
            env=self._get_env(),
            capture_output=True,
            text=True
        )
        output = result.stdout.strip()
        error = result.stderr.strip()

        return (result.returncode == 0, output, error)