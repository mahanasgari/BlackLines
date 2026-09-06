const MAX_EDGE = 1600;
const JPEG_QUALITY = 0.82;
const MAX_BYTES = 7 * 1024 * 1024;

function isPdf(file: File) {
  return file.type === "application/pdf" || /\.pdf$/i.test(file.name);
}

function isImage(file: File) {
  return file.type.startsWith("image/") || /\.(jpe?g|png|webp|heic|heif|gif)$/i.test(file.name);
}

function loadImage(file: File): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.onload = () => {
      URL.revokeObjectURL(url);
      resolve(img);
    };
    img.onerror = () => {
      URL.revokeObjectURL(url);
      reject(new Error("این عکس قابل خواندن نیست — JPG یا PNG بفرستید"));
    };
    img.src = url;
  });
}

async function canvasToJpeg(img: HTMLImageElement): Promise<File> {
  const scale = Math.min(1, MAX_EDGE / Math.max(img.width || 1, img.height || 1));
  const width = Math.max(1, Math.round((img.width || 1) * scale));
  const height = Math.max(1, Math.round((img.height || 1) * scale));
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext("2d");
  if (!ctx) throw new Error("آماده‌سازی عکس ناموفق بود");
  ctx.drawImage(img, 0, 0, width, height);
  const blob = await new Promise<Blob>((resolve, reject) => {
    canvas.toBlob(
      (out) => (out ? resolve(out) : reject(new Error("فشرده‌سازی عکس ناموفق بود"))),
      "image/jpeg",
      JPEG_QUALITY,
    );
  });
  return new File([blob], "receipt.jpg", { type: "image/jpeg" });
}

export async function prepareReceiptFile(file: File): Promise<File> {
  if (isPdf(file)) {
    if (file.size > MAX_BYTES) {
      throw new Error("حجم PDF زیاد است — زیر ۷ مگابایت بفرستید");
    }
    return file;
  }
  if (!isImage(file) && file.size > 0) {
    throw new Error("فقط عکس یا PDF رسید قبول است");
  }
  if (!file.size) {
    throw new Error("فایل خالی است — دوباره از گالری انتخاب کنید");
  }
  try {
    const img = await loadImage(file);
    const compact = await canvasToJpeg(img);
    if (compact.size > 0 && compact.size < file.size) return compact;
    if (compact.size > 0 && compact.size <= MAX_BYTES) return compact;
  } catch (e) {
    if (file.size <= MAX_BYTES && file.type.startsWith("image/")) return file;
    throw e instanceof Error ? e : new Error("آماده‌سازی عکس ناموفق بود");
  }
  if (file.size > MAX_BYTES) {
    throw new Error("عکس خیلی بزرگ است — یک عکس کوچک‌تر از گالری بفرستید");
  }
  return file;
}
