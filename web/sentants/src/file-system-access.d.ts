// file-system-access.d.ts
interface FileSystemFileHandle {
    createWritable(): Promise<FileSystemWritableFileStream>;
  }
  
  interface FileSystemWritableFileStream {
    write(data: Blob | string): Promise<void>;
    close(): Promise<void>;
  }
  
  interface Window {
    showSaveFilePicker(options?: {
      suggestedName?: string;
      types?: { description: string; accept: { [key: string]: string[] } }[];
    }): Promise<FileSystemFileHandle>;
  }
  