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
        const result = model.endpoint + `?key=\$\{${root.apiKeyEnvVarName}\}`
        return result;
    }

    function buildRequestData(model: AiModel, messages, systemPrompt: string, temperature: real, tools: list<var>, filePath: string, thinkingEnabled: bool, thinkingLevel: int) {
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
                // Fallback: reconstruct parts with thought_signature
                const part = {
                    functionCall: { "name": message.functionName }
                };
                // Use saved signature, or skip validator as last resort (loaded chats)
                if (message.thoughtSignature) {
                    part.thought_signature = message.thoughtSignature;
                } else {
                    part.thought_signature = "skip_thought_signature_validator";
                }
                return {
                    "role": geminiApiRoleName,
                    "parts": [part]
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
                    { text: message.rawContent },
                    ...(message.fileBase64 && message.fileBase64.length > 0 ? [{
                        "inline_data": {
                            "mime_type": message.fileMimeType,
                            "data": message.fileBase64
                        }
                    }] : []),
                    ...(message.fileUri && message.fileUri.length > 0 ? [{ 
                        "file_data": {
                            "mime_type": message.fileMimeType,
                            "file_uri": message.fileUri
                        }
                    }] : [])
                ]
            }
        })
        if (filePath && filePath.length > 0) {
            const trimmedFilePath = CF.FileUtils.trimFileProtocol(filePath);
            contents[contents.length - 1].parts.unshift({
                inline_data: {
                    mime_type: fileMimeTypeSubstitutionString,
                    data: fileUriSubstitutionString
                }
            });
        }
        // Gemini 3 uses thinking_level (string), not thinking_budget (number)
        // Levels: minimal=off-ish, low, medium, high
        const geminiThinkingLevels = ["minimal", "low", "medium", "high"];
        const thinkingLevelStr = (thinkingEnabled && thinkingLevel > 0)
            ? geminiThinkingLevels[Math.min(thinkingLevel, 3)]
            : null;

        let generationConfig = {
            "temperature": temperature
        };
        if (thinkingLevelStr) {
            generationConfig["thinking_config"] = { "thinking_level": thinkingLevelStr };
        }
        let baseData = {
            "contents": contents,
            "tools": tools && tools.length > 0 ? tools : undefined,
            "system_instruction": {
                "parts": [{ text: systemPrompt }]
            },
            "generationConfig": generationConfig,
        };
        return model.extraParams ? Object.assign({}, baseData, model.extraParams) : baseData;
    }

    function buildAuthorizationHeader(apiKeyEnvVarName: string): string {
        return "";
    }

    function parseResponseLine(line, message) {
        if (line.startsWith("[")) {
            buffer += line.slice(1).trim();
        } else if (line === "]") {
            buffer += line.slice(0, -1).trim();
            return parseBuffer(message);
        } else if (line.startsWith(",")) {
            return parseBuffer(message);
        } else {
            buffer += line.trim();
        }
        return {};
    }

    function parseBuffer(message) {
        let finished = false;
        try {
            if (buffer.length === 0) return {};
            const dataJson = JSON.parse(buffer);

            // Uploaded file (legacy File API)
            if (dataJson.uploadedFile) {
                message.fileUri = dataJson.uploadedFile.uri;
                message.fileMimeType = dataJson.uploadedFile.mimeType;
                return ({})
            }

            // Inline file (base64 approach)
            if (dataJson.inlineFile) {
                message.fileBase64 = dataJson.inlineFile.data;
                message.fileMimeType = dataJson.inlineFile.mimeType;
                return ({})
            }

            // Error response handling
            if (dataJson.error) {
                const errorMsg = `**Error ${dataJson.error.code}**: ${dataJson.error.message}`;
                message.rawContent += errorMsg;
                message.content += errorMsg;
                return { finished: true };
            }

            // No candidates?
            if (!dataJson.candidates) return {};

            // Finished?
            if (dataJson.candidates[0]?.finishReason) {
                finished = true;
            }

            const parts = dataJson.candidates[0]?.content?.parts;
            if (!parts || parts.length === 0) return { finished: finished };

            // Find functionCall part (use for-loop, .find() unreliable in QML)
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
                message.functionCall = functionCall.name;
                // Save full parts including thought_signature for correct history replay
                message.functionCallParts = parts;
                // Also save thought_signature separately for fallback (e.g. loaded chats)
                const sig = functionCallPart.thought_signature ?? functionCallPart.thoughtSignature ?? null;
                if (sig) message.thoughtSignature = sig;
                // Only add to rawContent (for API context), NOT to content (for UI)
                const rawEntry = `\n\n[[ Function: ${functionCall.name}(${JSON.stringify(functionCall.args)}) ]]\n`;
                message.rawContent += rawEntry;
                // Don't touch message.content — handleFunctionCall will add the UI representation
                return { functionCall: { name: functionCall.name, args: functionCall.args }, finished: finished };
            }

            // Find text part — skip pure thought chunks (thoughtSignature only, no text)
            let textPart = null;
            for (let i = 0; i < parts.length; i++) {
                if (parts[i] && parts[i].text !== undefined && parts[i].text !== null) {
                    textPart = parts[i];
                    break;
                }
            }
            if (!textPart) return { finished: finished };

            // Normal text response — write to rawContent only; flush timer syncs to content
            const responseContent = textPart.text;
            message.rawContent += responseContent;

            // Handle annotations and metadata
            const annotationSources = dataJson.candidates[0]?.groundingMetadata?.groundingChunks?.map(chunk => {
                return {
                    "type": "url_citation",
                    "text": chunk?.web?.title,
                    "url": chunk?.web?.uri,
                }
            }) ?? [];

            const annotations = dataJson.candidates[0]?.groundingMetadata?.groundingSupports?.map(citation => {
                return {
                    "type": "url_citation",
                    "start_index": citation.segment?.startIndex,
                    "end_index": citation.segment?.endIndex,
                    "text": citation?.segment.text,
                    "url": annotationSources[citation.groundingChunkIndices[0]]?.url,
                    "sources": citation.groundingChunkIndices
                }
            });
            message.annotationSources = annotationSources;
            message.annotations = annotations;
            message.searchQueries = dataJson.candidates[0]?.groundingMetadata?.webSearchQueries ?? [];

            // Usage metadata
            if (dataJson.usageMetadata) {
                return {
                    tokenUsage: {
                        input: dataJson.usageMetadata.promptTokenCount ?? -1,
                        output: dataJson.usageMetadata.candidatesTokenCount ?? -1,
                        total: dataJson.usageMetadata.totalTokenCount ?? -1
                    },
                    finished: finished
                };
            }

        } catch (e) {
            // Don't dump raw buffer to UI — just log
            console.log("[AI] Gemini: Could not parse buffer: ", e);
        } finally {
            buffer = "";
        }
        return { finished: finished };
    }

    function onRequestFinished(message) {
        return parseBuffer(message);
    }
    
    function reset() {
        buffer = "";
    }

    function buildScriptFileSetup(filePath) {
        const trimmedFilePath = CF.FileUtils.trimFileProtocol(filePath);
        let content = ""
        // Use base64 inline data instead of File API upload to avoid URI issues
        content += `IMAGE_PATH='${CF.StringUtils.shellSingleQuoteEscape(trimmedFilePath)}'\n`;
        content += `${fileMimeTypeVarName}=$(file -b --mime-type "$IMAGE_PATH")\n`;
        content += `${fileUriVarName}=$(base64 -w0 "$IMAGE_PATH")\n`;
        content += `printf '{"inlineFile": {"data": "%s", "mimeType": "%s"}}\\n,\\n' "$${fileUriVarName}" "$${fileMimeTypeVarName}"\n`;
        return content
    }

    function finalizeScriptContent(scriptContent: string): string {
        return scriptContent
            .replace(fileMimeTypeSubstitutionString, `'"\$${fileMimeTypeVarName}"'`)
            .replace(fileUriSubstitutionString, `'"\$${fileUriVarName}"'`);
    }
}
