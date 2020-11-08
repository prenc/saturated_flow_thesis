import os
import subprocess
import time
from shutil import rmtree

from ModelAnalyzer.DefaultParamsKeeper import DefaultParamsKeeper
from ModelAnalyzer.settings import (
    COMPILED_DUMP,
    PROFILING_DUMP,
    SUMMARIES_DUMP,
    CMAKE_BUILD_DIR,
    CMAKE_LISTS_PATH
)
from ModelAnalyzer.test_steps.ParamsGenerator import ParamsGenerator
from ModelAnalyzer.test_steps.ProgramCompiler import (
    ProgramCompiler,
)
from ModelAnalyzer.test_steps.ResultsHandler import ResultsHandler
from ModelAnalyzer.test_steps.ProgramRunner import ProgramRunner
from enum import Enum

class TestCaseHandler:
    class Mode(Enum):
        COMPILATION = 1
        RUNNER = 2

    def __init__(self, script_time, mode=Mode.RUNNER):
        self.mode = mode
        self._create_dirs(mode)
        self.script_start_time = script_time

    def _create_dirs(self, mode):
        dirs = [COMPILED_DUMP, CMAKE_BUILD_DIR]
        if mode == self.Mode.RUNNER:
            dirs.extend([ PROFILING_DUMP, SUMMARIES_DUMP])
        for dir_path in dirs:
            if not os.path.exists(dir_path):
                os.makedirs(dir_path)

    @staticmethod
    def _build_test():
        subprocess.run(
            [
                "cmake",
                f"-B{CMAKE_BUILD_DIR}",
                f"-H{CMAKE_LISTS_PATH}"
            ]
        )

    @staticmethod
    def _clean_build():
        rmtree(CMAKE_BUILD_DIR, ignore_errors=True)

    def perform_test_compilation(self, test_name, test_params):
        dpk = DefaultParamsKeeper()
        pg = ParamsGenerator(test_name)
        self._build_test()
        pcomp = ProgramCompiler(test_params["targets"])

        dpk.create_params_copy()

        for test_spec in self._prepare_test_specs(test_params["params"]):
            pg.generate(test_spec)
            pcomp.compile_test(test_spec)

        dpk.restore_params()
        self._clean_build()

    def perform_test_case(self, test_name, test_params):
        if self.mode == self.Mode.COMPILATION:
            self.perform_test_compilation(test_name, test_params)
        else:
            self.compile_and_run_test_case(test_name, test_params)

    def compile_and_run_test_case(self, test_name, test_params):
        dpk = DefaultParamsKeeper()
        pg = ParamsGenerator(test_name)
        self._build_test()
        pcomp = ProgramCompiler(test_params["targets"])

        prun = ProgramRunner(test_params["targets"])
        rg = ResultsHandler(
            test_name,
            self.script_start_time,
            chart_params=test_params.get("chart_params", None),
        )

        dpk.create_params_copy()
        result_paths = []

        test_case_start_time = time.time()
        for test_spec in self._prepare_test_specs(test_params["params"]):
            pg.generate(test_spec)
            executables = pcomp.compile_test(test_spec)
            intermediate_results_path = prun.perform_test(test_spec, executables_data=executables)
            result_paths.extend(intermediate_results_path)
        test_case_elapsed_time = time.time() - test_case_start_time

        dpk.restore_params()
        self._clean_build()
        return rg.save_results(result_paths, round(test_case_elapsed_time))

    @staticmethod
    def _prepare_test_specs(test_specs):
        return [
            {k: v for k, v in zip(test_specs.keys(), v)}
            for v in zip(*test_specs.values())
        ]
