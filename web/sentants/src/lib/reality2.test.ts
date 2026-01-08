/**
 * Tests for Reality2 GraphQL Client
 */

import { describe, it, expect, beforeEach } from "vitest";
import R2 from "./reality2";

describe("R2 Client", () => {
  let client: R2;

  beforeEach(() => {
    client = new R2("localhost", 4005, true);
  });

  describe("Constructor", () => {
    it("should create client with HTTPS URLs when ssl=true", () => {
      expect(client._graphql_http_url).toBe("https://localhost:4005/reality2");
      expect(client._graphql_webs_url).toBe(
        "wss://localhost:4005/reality2/websocket"
      );
      expect(client._secure).toBe(true);
    });

    it("should create client with HTTP URLs when ssl=false", () => {
      const insecureClient = new R2("localhost", 4005, false);
      expect(insecureClient._graphql_http_url).toBe(
        "http://localhost:4005/reality2"
      );
      expect(insecureClient._graphql_webs_url).toBe(
        "ws://localhost:4005/reality2/websocket"
      );
      expect(insecureClient._secure).toBe(false);
    });

    it("should use custom domain and port", () => {
      const customClient = new R2("192.168.1.100", 8080, true);
      expect(customClient._graphql_http_url).toBe(
        "https://192.168.1.100:8080/reality2"
      );
      expect(customClient._graphql_webs_url).toBe(
        "wss://192.168.1.100:8080/reality2/websocket"
      );
    });
  });

  describe("JSONPath utility", () => {
    it("should navigate simple paths", () => {
      const data = { name: "test", id: 123 };
      expect(R2.JSONPath(data, "name")).toBe("test");
      expect(R2.JSONPath(data, "id")).toBe(123);
    });

    it("should navigate nested paths", () => {
      const data = {
        data: {
          sentantGet: {
            name: "MySentant",
            id: "abc123",
          },
        },
      };
      expect(R2.JSONPath(data, "data.sentantGet.name")).toBe("MySentant");
      expect(R2.JSONPath(data, "data.sentantGet.id")).toBe("abc123");
    });

    it("should handle array indices", () => {
      const data = {
        items: [
          { name: "first" },
          { name: "second" },
          { name: "third" },
        ],
      };
      expect(R2.JSONPath(data, "items.0.name")).toBe("first");
      expect(R2.JSONPath(data, "items.1.name")).toBe("second");
      expect(R2.JSONPath(data, "items.2.name")).toBe("third");
    });

    it("should return null for non-existent paths", () => {
      const data = { name: "test" };
      expect(R2.JSONPath(data, "nonexistent")).toBeNull();
      expect(R2.JSONPath(data, "name.nested.deep")).toBeNull();
    });

    it("should handle arrays correctly", () => {
      const data = { list: ["a", "b", "c"] };
      expect(R2.JSONPath(data, "list.0")).toBe("a");
      expect(R2.JSONPath(data, "list.1")).toBe("b");
      expect(R2.JSONPath(data, "list.5")).toBeUndefined();
    });
  });

  describe("Type conversion utilities", () => {
    it("should convert string to number", () => {
      expect(R2.ToSimple("123")).toBe(123);
      expect(R2.ToSimple("3.14")).toBe(3.14);
    });

    it("should convert string to boolean", () => {
      expect(R2.ToSimple("true")).toBe(true);
      expect(R2.ToSimple("false")).toBe(false);
      expect(R2.ToSimple("TRUE")).toBe(true);
      expect(R2.ToSimple("FALSE")).toBe(false);
    });

    it("should pass through numbers", () => {
      expect(R2.ToSimple(42)).toBe(42);
      expect(R2.ToSimple(3.14159)).toBe(3.14159);
    });

    it("should pass through booleans", () => {
      expect(R2.ToSimple(true)).toBe(true);
      expect(R2.ToSimple(false)).toBe(false);
    });

    it("should stringify objects", () => {
      const obj = { key: "value" };
      const result = R2.ToSimple(obj);
      expect(typeof result).toBe("string");
      expect(result).toBe(JSON.stringify(obj));
    });

    it("should stringify arrays", () => {
      const arr = [1, 2, 3];
      const result = R2.ToSimple(arr);
      expect(typeof result).toBe("string");
      expect(result).toBe(JSON.stringify(arr));
    });
  });
});
