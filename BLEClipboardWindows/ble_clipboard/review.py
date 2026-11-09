"""A run can only use the frozen output of the most recent explicit review."""

from .macros import compile_macro


class RunReview:
    def __init__(self):
        self.compiled = None
        self.confirmed = False
        self.error = None

    def invalidate(self):
        self.compiled = None
        self.confirmed = False

    def prepare(self, macro, **context):
        self.invalidate()
        try:
            self.compiled = compile_macro(macro, **context)
            self.error = None
        except ValueError as error:
            self.error = str(error)
        return self.compiled

    def consume(self):
        if not self.confirmed or self.compiled is None:
            raise ValueError("Review and confirm the expanded output first.")
        compiled = self.compiled
        self.invalidate()
        return compiled
