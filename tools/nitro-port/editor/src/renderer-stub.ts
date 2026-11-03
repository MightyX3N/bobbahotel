// Stand-ins for the parts of @nitrots/nitro-renderer that nitro-react's avatar editor logic uses.
// Only what the logic needs: no pictures (the thumbnails' pictures are drawn by the game).
export const AvatarEditorFigureCategory = { GENERIC: 'generic', HEAD: 'head', TORSO: 'torso', LEGS: 'legs', WARDROBE: 'wardrobe', EFFECTS: 'effects' };
export const AvatarScaleType = { LARGE: 'h', SMALL: 'sh' };
export const AvatarSetType = { FULL: 'full', HEAD: 'head' };
export const AvatarFigurePartType = {
    LEFT_HAND_ITEM: 'li', LEFT_HAND: 'lh', LEFT_SLEEVE: 'ls', LEFT_COAT_SLEEVE: 'lc', BODY: 'bd', SHOES: 'sh', LEGS: 'lg', CHEST: 'ch',
    CHEST_ACCESSORY: 'ca', COAT_CHEST: 'cc', CHEST_PRINT: 'cp', WAIST_ACCESSORY: 'wa', RIGHT_HAND: 'rh', RIGHT_SLEEVE: 'rs', RIGHT_COAT_SLEEVE: 'rc',
    HEAD: 'hd', FACE: 'fc', EYES: 'ey', HAIR: 'hr', HAIR_BIG: 'hrb', FACE_ACCESSORY: 'fa', EYE_ACCESSORY: 'ea', HEAD_ACCESSORY: 'ha',
    HEAD_ACCESSORY_EXTRA: 'he', RIGHT_HAND_ITEM: 'ri'
};
export class NitroAlphaFilter { constructor(public alpha: number) {} }
export class NitroContainer { filters: any[]; addChild() {} destroy() {} }
export class NitroSprite { position = { set() {} }; tint = 0; constructor(public texture: any) {} }
export const TextureUtils = { generateImageUrl: (c: any) => 'image' };
export const ColorConverter = { int2rgb: (c: number) => '#' + ('00000' + (c >>> 0).toString(16)).slice(-6) };
export { AvatarFigureContainer } from './AvatarFigureContainer';
export type IPartColor = any; export type IFigurePartSet = any; export type IPalette = any; export type SetType = any;
export type IAvatarImageListener = any; export type IAvatarRenderManager = any; export type IFigurePart = any; export type IGraphicAsset = any;
export type IAvatarFigureContainer = any;
