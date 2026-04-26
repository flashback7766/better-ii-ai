import QtQuick
import qs.modules.common.functions as CF

ApiStrategy {
    readonly property string apiKeyEnvVarName: "API_KEY"
    readonly property string fileUriVarName: "file_uri"
    readonly property string fileMimeTypeVarName: "MIME_TYPE"
    readonly property string fileUriSubstitutionString: "{{ fileUriVarName }}"
    readonly property string fileMimeTypeSubstitutionString: "{{ fileMimeTypeVarName }}"
    property string buffer: ""
    
    function buildEndpoint(model: AiModel): string {
        const result = model.endpoint + `?key=\$\{${apiKeyEnvVarName}\}`
        return result;
    }

    function buildRequestData(model: AiModel, messages, systemPrompt: string, temperature: real, tools: list<var>, filePath: string) {
        console.log("[AI] Gemini Request Start: " + model.model);
        let contents = messages.map(message => {
            const geminiApiRoleName = (message.role === "assistant") ? "model" : message.role;
            const usingSearch = tools[0]?.google_search !== undefined
            if (!usingSearch && message.functionCall != undefined && message.functionName.length > 0) {
                // Use saved parts (includes thought_signature from API response)
                if (message.functionCallParts && message.functionCallParts.length > 0) {
                    return {
                        "role": geminiApiRoleName,
                        "parts": message.functionCallParts
                    }
                }
                return {
                    "role": geminiApiRoleName,
                    "parts": [{ functionCall: { "name": message.functionName, "args": message.functionCall?.args ?? {} } }]
                }
            }
            if (!usingSearch && message.functionResponse != undefined && message.functionName.length > 0) {
                return {
                    "role": geminiApiRoleName,
                    "parts": [{ 
                        functionResponse: {
                            "name": message.functionName,
                            "response": { "content": message.functionResponse }
                        }
                    }]
                }
            }
            return {
                "role": geminiApiRoleName,
                "parts": [
                    { text: message.rawContent || " " },
                    // Inline binary data (images, etc)
                    ...(message.fileBase64 && message.fileBase64.length > 0 ? [{
                        "inline_data": {
                            "mime_type": message.fileMimeType,
                            "data": message.fileBase64
                        }
                    }] : []),
                    // File URI (uploaded via File API)
                    ...(message.fileUri && message.fileUri.length > 0 ? [{ 
                        "file_data": {
                            "mime_type": message.fileMimeType,
                            "file_uri": message.fileUri
                        }
                    }] : []),
                    // Text file content (non-image files read as text)
                    ...(message.fileTextContent && message.fileTextContent.length > 0 ? [{
                        "text": "[Attached file: " + (message.localFilePath ? message.localFilePath.split("/").pop() : "file") + " (" + (message.fileMimeType || "text") + ")]\n```\n" + message.fileTextContent + "\n```"
                    }] : [])
                ]
            }
        })
        if (filePath && filePath.length > 0) {
            contents[contents.length - 1].parts.unshift({
                inline_data: {
                    mime_type: fileMimeTypeSubstitutionString,
                    data: fileUriSubstitutionString
                }
            });
        }
        
        let generationConfig = {
            "temperature": temperature,
            "topP": 0.95,
            "topK": 40,
            "maxOutputTokens": 8192,
        };

        // Gemini requires alternating roles (user, model, user, model).
        let alternatingContents = [];
        if (contents.length > 0) {
            let lastRole = "";
            for (let i = 0; i < contents.length; i++) {
                if (contents[i].role === lastRole && alternatingContents.length > 0) {
                    alternatingContents[alternatingContents.length - 1].parts = 
                        alternatingContents[alternatingContents.length - 1].parts.concat(contents[i].parts);
                } else {
                    alternatingContents.push(contents[i]);
                    lastRole = contents[i].role;
                }
            }
        }

        const requestData = {
            "contents": alternatingContents,
            "generationConfig": generationConfig
        };

        if (systemPrompt && systemPrompt.length > 0) {
            requestData.system_instruction = { "parts": [{ "text": systemPrompt }] };
        }

        if (tools && tools.length > 0) {
            requestData.tools = tools;
        }

        print("[AI] Gemini Request: " + alternatingContents.length + " messages");
        return model.extraParams ? Object.assign({}, requestData, model.extraParams) : requestData;
    }

    function buildAuthorizationHeader(apiKeyEnvVarName: string): string {
        return "";
    }

    function parseResponseLine(line, message) {
        let cleanLine = line.trim();
        if (cleanLine.length === 0) return {};
        
        // Accumulate line to buffer
        buffer += cleanLine;
        
        // Try to parse what we have.
        return parseBuffer(message, true);
    }

    function parseBuffer(message, isPartial = false) {
        if (buffer.length === 0) return {};
        
        // Clean up the buffer to attempt parsing a single JSON object
        let workBuffer = buffer.trim();
        
        // Strip array brackets and commas if they are at the very edges
        if (workBuffer.startsWith("[")) workBuffer = workBuffer.slice(1).trim();
        if (workBuffer.startsWith(",")) workBuffer = workBuffer.slice(1).trim();
        if (workBuffer.endsWith("]")) workBuffer = workBuffer.slice(0, -1).trim();
        if (workBuffer.endsWith(",")) workBuffer = workBuffer.slice(0, -1).trim();
        
        if (workBuffer.length === 0) return {};

        let finished = false;
        try {
            const dataJson = JSON.parse(workBuffer);
            // If parsing succeeded, it means we got a complete JSON object.
            // Clear the MAIN buffer.
            buffer = ""; 

            // Uploaded file (legacy File API)
            if (dataJson.uploadedFile) {
                message.fileUri = dataJson.uploadedFile.uri;
                message.fileMimeType = dataJson.uploadedFile.mimeType;
                return ({})
            }

            // Inline file (base64 approach for images)
            if (dataJson.inlineFile) {
                message.fileBase64 = dataJson.inlineFile.data;
                message.fileMimeType = dataJson.inlineFile.mimeType;
                return ({});
            }

            // Text file (non-image content extracted by shell)
            if (dataJson.textFile) {
                message.fileTextContent = dataJson.textFile.content;
                message.fileMimeType = dataJson.textFile.mimeType;
                if (dataJson.textFile.name) message.localFilePath = dataJson.textFile.name;
                return ({});
            }

            // Error response handling
            if (dataJson.error) {
                const errorMsg = `**Error ${dataJson.error.code}**: ${dataJson.error.message}`;
                message.rawContent += errorMsg;
                return { finished: true };
            }

            // No candidates?
            if (!dataJson.candidates) return {};

            // Finished?
            if (dataJson.candidates[0]?.finishReason && dataJson.candidates[0]?.finishReason !== "STOP") {
                finished = true;
            }

            const parts = dataJson.candidates[0]?.content?.parts;
            if (!parts || parts.length === 0) return { finished: finished };

            // Find and process parts
            for (let i = 0; i < parts.length; i++) {
                const part = parts[i];
                if (!part) continue;

                // Handle text parts
                const text = part.text || "";
                if (text && text.length > 0) {
                    message.rawContent += text;
                }
                
                // Handle thinking/reasoning parts (Gemini 3.1 Pro might use 'thought')
                // We keep it invisible as requested, but we could log it for debug
                const thought = part.thought || "";
                if (thought && thought.length > 0) {
                    console.log("[AI] Gemini Thought: " + thought);
                }
            }

            // Find functionCall part
            let functionCallPart = null;
            for (let i = 0; i < parts.length; i++) {
                if (parts[i] && parts[i].functionCall) {
                    functionCallPart = parts[i];
                    break;
                }
            }
            if (functionCallPart) {
                const functionCall = functionCallPart.functionCall;
                message.functionName = functionCall.name;
                message.functionCall = { name: functionCall.name, args: functionCall.args ?? {} };
                message.functionCallParts = parts;
                const rawEntry = `\n\n[[ Function: ${functionCall.name}(${JSON.stringify(functionCall.args)}) ]]\n`;
                message.rawContent += rawEntry;
                return { functionCall: { name: functionCall.name, args: functionCall.args }, finished: finished };
            }

            // Token Usage
            if (dataJson.usageMetadata) {
                return {
                    tokenUsage: {
                        input: dataJson.usageMetadata.promptTokenCount ?? -1,
                        output: dataJson.usageMetadata.candidatesTokenCount ?? -1,
                        total: dataJson.usageMetadata.totalTokenCount ?? -1,
                    },
                    finished: finished
                };
            }

        } catch (e) {
            // Only log errors if we're not in the middle of a partial line
            if (!isPartial) console.log("[AI] Gemini: Could not parse buffer: ", e);
        }
        return { finished: finished };
    }

    function onRequestFinished(message) {
        const result = parseBuffer(message);
        if (message._thinkOpen) {
            message.rawContent += "\n</think>\n\n";
            message._thinkOpen = false;
        }
        return result;
    }
    
    function reset() {
        buffer = "";
    }

    function buildScriptFileSetup(filePath) {
        const trimmedFilePath = CF.FileUtils.trimFileProtocol(filePath);
        const escapedPath = CF.StringUtils.shellSingleQuoteEscape(trimmedFilePath);
        let content = "";
        content += "IMAGE_PATH='" + escapedPath + "'\n";
        content += fileMimeTypeVarName + "=$(file -b --mime-type \"$IMAGE_PATH\")\n";
        // For images: encode as base64 inline data (Gemini native)
        // For other types: read as text content
        content += "if echo \"$" + fileMimeTypeVarName + "\" | grep -qE '^(image|audio|video)/'; then\n";
        content += "  " + fileUriVarName + "=$(base64 -w0 \"$IMAGE_PATH\")\n";
        content += "  printf '{\"inlineFile\": {\"data\": \"%s\", \"mimeType\": \"%s\"}}\\n,\\n' \"$" + fileUriVarName + "\" \"$" + fileMimeTypeVarName + "\"\n";
        content += "else\n";
        content += "  ATTACH_TEXT=$(head -c 100000 \"$IMAGE_PATH\" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || head -c 50000 \"$IMAGE_PATH\")\n";
        content += "  ATTACH_NAME=$(basename \"$IMAGE_PATH\")\n";
        content += "  printf '{\"textFile\": {\"content\": %s, \"mimeType\": \"%s\", \"name\": \"%s\"}}\\n,\\n' \"$ATTACH_TEXT\" \"$" + fileMimeTypeVarName + "\" \"$ATTACH_NAME\"\n";
        content += "fi\n";
        return content;
    }

    function finalizeScriptContent(scriptContent: string): string {
        return scriptContent
            .replace(fileMimeTypeSubstitutionString, `'"\$${fileMimeTypeVarName}"'`)
            .replace(fileUriSubstitutionString, `'"\$${fileUriVarName}"'`);
    }
}
