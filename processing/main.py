import uvicorn
import os
import sys

def main():
    # Make sure execution context can locate local imports properly
    sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    
    port = 8765
    print(f"Starting DubForge macOS Python Pipeline Server on port {port}...")
    uvicorn.run("processing.api_server:app", host="127.0.0.1", port=port, reload=False)

if __name__ == "__main__":
    main()
