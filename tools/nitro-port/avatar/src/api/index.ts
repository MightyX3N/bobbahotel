// [bobba] The parts of Nitro's api the avatar code uses: the real enums and classes, and its
// interfaces as 'any' (they are only types).
export * from './AvatarDirectionAngle';
export * from './AvatarScaleType';
export * from './AvatarSetType';
export * from './GeometryType';
export * from './AvatarFigurePartType';
export * from './AvatarAction';
export * from './AdvancedMap';
export * from './RoomObjectSpriteData';
export type IActionDefinition = import('../nitro/avatar/actions/ActionDefinition').ActionDefinition;
export type IActiveActionData = import('../nitro/avatar/actions/ActiveActionData').ActiveActionData;
export type IAdvancedMap<T = any, U = any> = import('./AdvancedMap').AdvancedMap<T, U>;
export type IAnimation = import('../nitro/avatar/animation/Animation').Animation;
export type IAnimationLayerData = import('../nitro/avatar/animation/AvatarAnimationLayerData').AvatarAnimationLayerData;
export type IAnimationManager = import('../nitro/avatar/animation/AnimationManager').AnimationManager;
export type IAssetAlias = any;
export type IAssetAnimation = any;
export type IAssetAnimationAdd = any;
export type IAssetAnimationAvatar = any;
export type IAssetAnimationDirection = any;
export type IAssetAnimationFrame = any;
export type IAssetAnimationFramePart = any;
export type IAssetAnimationSprite = any;
export type IAssetManager = any;
export type IAvatarAssetDownloadLibrary = any;
export type IAvatarDataContainer = import('../nitro/avatar/animation/AvatarDataContainer').AvatarDataContainer;
export type IAvatarEffectListener = any;
export type IAvatarFigureContainer = import('../nitro/avatar/AvatarFigureContainer').AvatarFigureContainer;
export type IAvatarImage = import('../nitro/avatar/AvatarImage').AvatarImage;
export type IAvatarImageListener = any;
export type IAvatarRenderManager = any;
export type IEffectAssetDownloadLibrary = any;
export type IFigureData = any;
export type IFigureDataColor = any;
export type IFigureDataPalette = any;
export type IFigureDataPart = any;
export type IFigureDataSet = any;
export type IFigureDataSetType = any;
export type IFigurePart = import('../nitro/avatar/structure/figure/FigurePart').FigurePart;
export type IFigurePartSet = import('../nitro/avatar/structure/figure/FigurePartSet').FigurePartSet;
export type IFigureSetData = any;
export interface IGraphicAsset
{
    name: string;
    texture: any;
    x: number;
    y: number;
    width: number;
    height: number;
    rectangle: any;
}
export type INitroEvent = any;
export type IPalette = import('../nitro/avatar/structure/figure/Palette').Palette;
export type IPartColor = import('../nitro/avatar/structure/figure/PartColor').PartColor;
export type IPetCustomPart = any;
export type ISetType = import('../nitro/avatar/structure/figure/SetType').SetType;
export type ISpriteDataContainer = import('../nitro/avatar/animation/SpriteDataContainer').SpriteDataContainer;
export type IStructureData = any;
