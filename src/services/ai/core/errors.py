class OpenAIClientError(Exception):
    pass


class OpenAIClientUnavailableError(OpenAIClientError):
    pass


class OpenAIRequestError(OpenAIClientError):
    pass


class OpenAIResponseFormatError(OpenAIClientError):
    pass
