export function splitConcatenatedJSON(jsonString: string): any[] {
    const objects: any[] = [];
    let braceLevel = 0;
    let start = 0;

    for (let i = 0; i < jsonString.length; i++) {
        const char = jsonString[i];

        if (char === '{') {
            if (braceLevel === 0) {
                start = i;
            }
            braceLevel++;
        } else if (char === '}') {
            braceLevel--;
            if (braceLevel === 0) {
                try {
                    const jsonObj = JSON.parse(jsonString.slice(start, i + 1));
                    objects.push(jsonObj);
                } catch (e) {
                    console.error("Invalid JSON object:", e);
                }
            }
        }
    }

    return objects;
}