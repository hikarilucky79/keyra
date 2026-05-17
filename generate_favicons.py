import os
import shutil
from PIL import Image

def main():
    # Paths
    downloads_logo_path = "/home/hikari/Downloads/favicon.png"
    local_logo_path = "/home/hikari/Projetos/keyra/app_logo.png"
    fallback_logo_path = "/home/hikari/.gemini/antigravity/brain/4fb3c4fd-0851-441c-a93d-56e0157a36de/media__1778981990875.jpg"
    
    public_dir = "/home/hikari/Projetos/keyra/public"
    flutter_icons_dir = "/home/hikari/Projetos/keyra/keyra-flutter/assets/icons"

    # Ensure directories exist
    os.makedirs(public_dir, exist_ok=True)
    os.makedirs(flutter_icons_dir, exist_ok=True)

    # 1. Copy the source image from downloads or fallback to the local workspace if needed
    src_image_path = None
    if os.path.exists(downloads_logo_path):
        print(f"Found source image in Downloads: {downloads_logo_path}")
        try:
            shutil.copy(downloads_logo_path, local_logo_path)
            src_image_path = local_logo_path
            print(f"Copied source image to workspace: {local_logo_path}")
        except Exception as e:
            print(f"Notice: Could not copy file directly (might be sandbox restrictions): {e}")
            src_image_path = downloads_logo_path
    elif os.path.exists(local_logo_path):
        src_image_path = local_logo_path
    elif os.path.exists(fallback_logo_path):
        src_image_path = fallback_logo_path

    if not src_image_path or not os.path.exists(src_image_path):
        print(f"Error: Source image not found.")
        print(f"Please copy the favicon.png file to your workspace: cp {downloads_logo_path} {local_logo_path}")
        return

    print(f"Loading source image from {src_image_path}...")
    try:
        img = Image.open(src_image_path)
    except Exception as e:
        print(f"Error opening source image: {e}")
        return

    # Convert to RGBA for transparent/clean borders
    if img.mode != 'RGBA':
        img = img.convert('RGBA')

    # Define standard web favicon sizes
    sizes = {
        "favicon-16x16.png": (16, 16),
        "favicon-32x32.png": (32, 32),
        "apple-touch-icon.png": (180, 180),
        "android-chrome-192x192.png": (192, 192),
        "android-chrome-512x512.png": (512, 512),
    }

    # Generate PNG files in public directory
    for filename, size in sizes.items():
        dest_path = os.path.join(public_dir, filename)
        resized_img = img.resize(size, Image.Resampling.LANCZOS)
        resized_img.save(dest_path, "PNG")
        print(f"Saved: {dest_path}")

    # Generate a standard favicon.png (512x512)
    favicon_png_path = os.path.join(public_dir, "favicon.png")
    img.resize((512, 512), Image.Resampling.LANCZOS).save(favicon_png_path, "PNG")
    print(f"Saved default favicon.png: {favicon_png_path}")

    # Generate multi-size favicon.ico (16x16, 32x32, 48x48) in public directory
    ico_path = os.path.join(public_dir, "favicon.ico")
    ico_img = img.resize((48, 48), Image.Resampling.LANCZOS)
    ico_img.save(
        ico_path,
        format="ICO",
        sizes=[(16, 16), (32, 32), (48, 48)]
    )
    print(f"Saved multi-size favicon.ico: {ico_path}")

    # Copy favicon.ico and favicon.png to flutter icons directory as well
    flutter_ico_path = os.path.join(flutter_icons_dir, "favicon.ico")
    ico_img.save(
        flutter_ico_path,
        format="ICO",
        sizes=[(16, 16), (32, 32), (48, 48)]
    )
    print(f"Saved flutter favicon.ico: {flutter_ico_path}")

    # Also update/replace keyra-flutter/assets/icons/tray_icon.png and app_icon.png
    tray_icon_path = os.path.join(flutter_icons_dir, "tray_icon.png")
    app_icon_path = os.path.join(flutter_icons_dir, "app_icon.png")
    
    # Tray icon is usually 32x32 or 64x64 on desktop systems
    img.resize((64, 64), Image.Resampling.LANCZOS).save(tray_icon_path, "PNG")
    print(f"Updated app tray icon: {tray_icon_path}")

    # App icon is high-res, e.g. 512x512
    img.resize((512, 512), Image.Resampling.LANCZOS).save(app_icon_path, "PNG")
    print(f"Updated app icon: {app_icon_path}")

    print("Favicon generation completed successfully!")

if __name__ == "__main__":
    main()
