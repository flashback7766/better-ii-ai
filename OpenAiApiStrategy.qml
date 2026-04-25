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
                    // Image attached via base64
                    if (message.role === "user" && message.fileBase64 && message.fileBase64.length > 0) {
                        const mediaType = message.fileMimeType || "image/png";
                        if (mediaType.startsWith("image/")) {
                            return {
                                "role": message.role,
                                "content": [
                                    {
                                        "type": "image_url",
                                        "image_url": {
                                            "url": "data:" + mediaType + ";base64," + message.fileBase64
                                        }
                                    },
                                    {
                                        "type": "text",
                                        "text": message.rawContent || "Describe this image."
                                    }
                                ]
                            };
                        } else {
                            // Non-image: decode base64 at request-build time isn't trivial,
                            // so we rely on fileTextContent pre-populated by parseResponseLine
                            const fileName = message.localFilePath ? message.localFilePath.split("/").pop() : "attached file";
                            return {
                                "role": message.role,
                                "content": [
                                    {
                                        "type": "text",
                                        "text": "[File: " + fileName + " (" + mediaType + ")]\n" + (message.fileTextContent || message.rawContent || "")
                                    }
                                ]
                            };
                        }
                    }
                    // Text file attached (non-image, content extracted by shell)
                    if (message.role === "user" && message.fileTextContent && message.fileTextContent.length > 0) {
                        const fileName = message.localFilePath ? message.localFilePath.split("/").pop() : "file";
                        return {
                            "role": message.role,
                            "content": "[Attached file: " + fileName + "]\n```\n" + message.fileTextContent + "\n```\n" + (message.rawContent || "")
                        };
                    }
                    return {
                        "role": message.role,
                        "content": message.rawContent,
                    }
                }),
            ],
            "stream": true,
            "temperature": temperature,
        };
        // Only include tools when non-empty — many APIs error on empty array
        if (tools && tools.length > 0) {
            baseData["tools"] = tools;
        }
        return model.extraParams ? Object.assign({}, baseData, model.extraParams) : baseData;
    }

    function buildAuthorizationHeader(apiKeyEnvVarName: string): string {
        return `-H "Authorization: Bearer \$\{${apiKeyEnvVarName}\}"`;
    }

    function buildScriptFileSetup(filePath) {
        const trimmedFilePath = filePath.replace(/^file:\/\//, "");
        const escapedPath = trimmedFilePath.replace(/'/g, "'\\''");
        let content = "";
        content += "ATTACH_PATH='" + escapedPath + "'\n";
        content += "ATTACH_MIME=$(file -b --mime-type \"$ATTACH_PATH\")\n";
        // Images: base64-encode and output as inlineFile JSON
        // Other files: read text content and output as textFile JSON
        content += "if echo \"$ATTACH_MIME\" | grep -qE '^image/'; then\n";
        content += "  ATTACH_B64=$(base64 -w0 \"$ATTACH_PATH\")\n";
        content += "  printf '{\"inlineFile\": {\"data\": \"%s\", \"mimeType\": \"%s\"}}\\n' \"$ATTACH_B64\" \"$ATTACH_MIME\"\n";
        content += "else\n";
        content += "  ATTACH_TEXT=$(head -c 100000 \"$ATTACH_PATH\" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || head -c 50000 \"$ATTACH_PATH\")\n";
        content += "  ATTACH_NAME=$(basename \"$ATTACH_PATH\")\n";
        content += "  printf '{\"textFile\": {\"content\": %s, \"mimeType\": \"%s\", \"name\": \"%s\"}}\\n' \"$ATTACH_TEXT\" \"$ATTACH_MIME\" \"$ATTACH_NAME\"\n";
        content += "fi\n";
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

            // Handle inlineFile from buildScriptFileSetup (images)
            if (dataJson.inlineFile) {
                message.fileBase64 = dataJson.inlineFile.data;
                message.fileMimeType = dataJson.inlineFile.mimeType;
                return {};
            }

            // Handle textFile from buildScriptFileSetup (non-image files)
            if (dataJson.textFile) {
                message.fileTextContent = dataJson.textFile.content;
                message.fileMimeType = dataJson.textFile.mimeType;
                if (dataJson.textFile.name) message.localFilePath = dataJson.textFile.name;
                return {};
            }

            // Error response handling
            if (dataJson.error) {
                const errorMsg = "**Error**: " + (dataJson.error.message || JSON.stringify(dataJson.error));
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
                    const rawEntry = "\n\n[[ Function: " + _toolCallName + "(" + _toolCallArgs + ") ]]\n";
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
