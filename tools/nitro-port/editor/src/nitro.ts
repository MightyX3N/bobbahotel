// nitro-react's api/nitro functions the editor logic uses, on figuredata loaded by the test.
import { AvatarFigureContainer } from './AvatarFigureContainer';
export const Env: any = { figureData: null, clubLevel: 0, config: {} as any };
export const GetAvatarSetType = (t: string) => Env.figureData.getSetType(t);
export const GetAvatarPalette = (id: number) => Env.figureData.getPalette(id);
export const GetClubMemberLevel = () => Env.clubLevel;
export function GetConfiguration<T>(key: string, value: T = null): T { return (key in Env.config) ? Env.config[key] : value; }
export const GetAvatarRenderManager = () => ({
    structure: { figureData: Env.figureData, getMandatorySetTypeIds: (g: string, l: number) => Env.figureData.getMandatorySetTypeIds(g, l) },
    getMandatoryAvatarPartSetIds: (g: string, l: number) => Env.figureData.getMandatorySetTypeIds(g, l),
    createFigureContainer: (f: string) => new AvatarFigureContainer(f),
    isFigureContainerReady: () => false,
    downloadAvatarFigure: () => {},
    createAvatarImage: () => ({ getImageAsSprite: (): any => null, dispose: () => {} }),
    getAssetByName: (): any => null,
});
