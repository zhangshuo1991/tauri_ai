import type { Component } from "vue";

import {
  ChatbubbleEllipsesOutline,
  CodeSlashOutline,
  ColorPaletteOutline,
  FlashOutline,
  GlobeOutline,
  ImageOutline,
  LayersOutline,
  PencilOutline,
  RocketOutline,
  SearchOutline,
  SettingsOutline,
  TerminalOutline,
} from "@vicons/ionicons5";

import customIconUrl from "../icons/custom.svg";
import deepseekIconUrl from "../icons/deepseek.svg";
import doubaoIconUrl from "../icons/doubao.svg";
import openaiIconUrl from "../icons/openai.svg";
import qianwenIconUrl from "../icons/qianwen.svg";

export type XiconKey = `xicon:${string}:${string}`;

export const assetIconUrlByName: Record<string, string> = {
  deepseek: deepseekIconUrl,
  doubao: doubaoIconUrl,
  openai: openaiIconUrl,
  qianwen: qianwenIconUrl,
  custom: customIconUrl,
};

export const xiconRegistry: Record<string, Record<string, Component>> = {
  ionicons5: {
    ChatbubbleEllipsesOutline,
    CodeSlashOutline,
    ColorPaletteOutline,
    FlashOutline,
    GlobeOutline,
    ImageOutline,
    LayersOutline,
    PencilOutline,
    RocketOutline,
    SearchOutline,
    SettingsOutline,
    TerminalOutline,
  },
};

export const xiconOptions: ReadonlyArray<{ key: XiconKey; label: string }> = [
  { key: "xicon:ionicons5:ChatbubbleEllipsesOutline", label: "Chat" },
  { key: "xicon:ionicons5:GlobeOutline", label: "Web" },
  { key: "xicon:ionicons5:SearchOutline", label: "Search" },
  { key: "xicon:ionicons5:RocketOutline", label: "Rocket" },
  { key: "xicon:ionicons5:FlashOutline", label: "Flash" },
  { key: "xicon:ionicons5:TerminalOutline", label: "Terminal" },
  { key: "xicon:ionicons5:CodeSlashOutline", label: "Code" },
  { key: "xicon:ionicons5:LayersOutline", label: "Layers" },
  { key: "xicon:ionicons5:PencilOutline", label: "Edit" },
  { key: "xicon:ionicons5:ColorPaletteOutline", label: "Palette" },
  { key: "xicon:ionicons5:ImageOutline", label: "Image" },
  { key: "xicon:ionicons5:SettingsOutline", label: "Settings" },
];

export function getIconUrl(icon: string): string {
  if (icon.startsWith("data:image/")) return icon;
  return assetIconUrlByName[icon] ?? assetIconUrlByName.custom;
}

export function getXiconComponentOrNull(icon: string): Component | null {
  if (!icon.startsWith("xicon:")) return null;
  const [, pack, name] = icon.split(":");
  return xiconRegistry[pack]?.[name] ?? null;
}

export function getIconTitle(icon: string): string {
  if (icon.startsWith("data:image/")) return "已上传图片";
  return icon;
}

export async function fileToSquarePngDataUrl(file: File, size: number): Promise<string> {
  const dataUrl = await new Promise<string>((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result));
    reader.onerror = () => reject(new Error("读取图片失败"));
    reader.readAsDataURL(file);
  });

  const image = await new Promise<HTMLImageElement>((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error("解析图片失败"));
    img.src = dataUrl;
  });

  const canvas = document.createElement("canvas");
  canvas.width = size;
  canvas.height = size;
  const ctx = canvas.getContext("2d");
  if (!ctx) throw new Error("Canvas 初始化失败");

  const sourceSize = Math.min(image.width, image.height);
  const sourceX = Math.floor((image.width - sourceSize) / 2);
  const sourceY = Math.floor((image.height - sourceSize) / 2);

  ctx.clearRect(0, 0, size, size);
  ctx.drawImage(image, sourceX, sourceY, sourceSize, sourceSize, 0, 0, size, size);
  return canvas.toDataURL("image/png");
}

