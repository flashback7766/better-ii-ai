import QtQuick

ApiStrategy {
    property bool isReasoning: false
    
    function buildEndpoint(model: AiModel): string {
        return model.endpoint;
    }

    function buildRequestData(model: AiModel, messages, systemPrompt: string, temperature: real, tools: list<var>, filePath: string, thinkingEnabled, thinkingLevel) {
        let baseData = {
            "model": model.model,
            "messages": [
                {role: "system", content: systemPrompt},
                ...messages.map(message => {
                    if (message.role === "user" && message.fileBase64 && message.fileBase64.length > 0) {
                        const mediaType = message.fileMimeType || "image/png";
                        return {
                            "role": message.role,
                            "content": [
                                {
                                    "type": "image_url",
                                    "image_url": {
                                        "url": `data:${mediaType};base64,${message.fileBase64}`
                                    }
                                },
                                {
                                    "type": "text",
                                    "text": message.rawContent || "Describe this image."
                                }
                            ]
                        };
                    }
                    return {
                        "role": message.role,
                        "content": message.rawContent,
                    }
                }),
            ],
            "stream": true,
            "tools": tools,
            "temperature": temperature,
        };
        return model.extraParams ? Object.assign({}, baseData, model.extraParams) : baseData;
    }

    function buildAuthorizationHeader(apiKeyEnvVarName: string): string {
        return `-H "Authorization: Bearer \$\{${apiKeyEnvVarName}\}"`;
    }

    function buildScriptFileSetup(filePath) {
        const trimmedFilePath = filePath.replace(/^file:\/\//, "");
        let content = "";
        content += `ATTACH_PATH='${trimmedFilePath.replace(/'/g, "'\\''") }'\n`;
        content += `ATTACH_MIME=$(file -b --mime-type "$ATTACH_PATH")\n`;
        content += `ATTACH_B64=$(base64 -w0 "$ATTACH_PATH")\n`;
        content += `printf '{"inlineFile": {"data": "%s", "mimeType": "%s"}}\\n' "$ATTACH_B64" "$ATTACH_MIME"\n`;
        return content;
    }

    // Accumulate streamed tool call fragments
    property string _toolCallName: ""
    property string _toolCallArgs: ""

    function parseResponseLine(line, message) {
        let cleanData = line.trim();
        if (cleanData.startsWith("data:")) {
            cleanData = cleanData.slice(5).trim();
        }
        
        if (!cleanData || cleanData.startsWith(":")) return {};
        if (cleanData === "[DONE]") {
            return { finished: true };
        }
        
        try {
            const dataJson = JSON.parse(cleanData);

            // Handle inlineFile from buildScriptFileSetup
            if (dataJson.inlineFile) {
                message.fileBase64 = dataJson.inlineFile.data;
                message.fileMimeType = dataJson.inlineFile.mimeType;
                return {};
            }

            // Error response handling
            if (dataJson.error) {
                const errorMsg = `**Error**: ${dataJson.error.message || JSON.stringify(dataJson.error)}`;
                message.rawContent += errorMsg;
                message.content += errorMsg;
                return { finished: true };
            }

            const delta = dataJson.choices?.[0]?.delta;
            const finishReason = dataJson.choices?.[0]?.finish_reason;

            // Handle tool calls (OpenAI function calling)
            if (delta?.tool_calls) {
                for (let i = 0; i < delta.tool_calls.length; i++) {
                    const tc = delta.tool_calls[i];
                    if (tc["function"]?.name) _toolCallName = tc["function"].name;
                    if (tc["function"]?.arguments) _toolCallArgs += tc["function"].arguments;
                }
                // If finish_reason is tool_calls, emit the function call
                if (finishReason === "tool_calls" || finishReason === "function_call") {
                    let args = {};
                    try { args = JSON.parse(_toolCallArgs); } catch(e) {}
                    const fc = { name: _toolCallName, args: args };
                    message.functionName = _toolCallName;
                    message.functionCall = fc;
                    const rawEntry = `\n\n[[ Function: ${_toolCallName}(${_toolCallArgs}) ]]\n`;
                    message.rawContent += rawEntry;
                    _toolCallName = "";
                    _toolCallArgs = "";
                    return { functionCall: fc, finished: false };
                }
                return {};
            }

            let newContent = "";
            const responseContent = delta?.content || dataJson.message?.content;
            const responseReasoning = delta?.reasoning || delta?.reasoning_content;

            if (responseContent && responseContent.length > 0) {
                if (isReasoning) {
                    isReasoning = false;
                    const endBlock = "\n\n</think>\n\n";
                    message.rawContent += endBlock;
                }
                newContent = responseContent;
            } else if (responseReasoning && responseReasoning.length > 0) {
                if (!isReasoning) {
                    isReasoning = true;
                    const startBlock = "\n\n<think>\n\n";
                    message.rawContent += startBlock;
                }
                newContent = responseReasoning;
            }

            // Write to rawContent only; flush timer syncs to content
            message.rawContent += newContent;

            // Check finish reason
            if (finishReason === "stop") {
                return { finished: true };
            }

            if (dataJson.usage) {
                return {
                    tokenUsage: {
                        input: dataJson.usage.prompt_tokens ?? -1,
                        output: dataJson.usage.completion_tokens ?? -1,
                        total: dataJson.usage.total_tokens ?? -1
                    }
                };
            }

            if (dataJson.done) {
                return { finished: true };
            }
            
        } catch (e) {
            // Don't dump unparseable lines to chat — log only
            console.log("[AI] OpenAI: Could not parse line: ", e);
        }
        
        return {};
    }
    
    function onRequestFinished(message) {
        return {};
    }
    
    function reset() {
        isReasoning = false;
        _toolCallName = "";
        _toolCallArgs = "";
    }

    function finalizeScriptContent(content) {
        return content;
    }
}
