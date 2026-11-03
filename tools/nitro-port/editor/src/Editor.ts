// nitro-react's AvatarEditorView, its state without React: the same steps on the same objects.
import { AvatarEditorFigureCategory } from './renderer-stub';
import { AvatarEditorUtilities } from './nitro-react/AvatarEditorUtilities';
import { BodyModel } from './nitro-react/BodyModel';
import { FigureData } from './nitro-react/FigureData';
import { generateRandomFigure } from './nitro-react/FigureGenerator';
import { HeadModel } from './nitro-react/HeadModel';
import { LegModel } from './nitro-react/LegModel';
import { TorsoModel } from './nitro-react/TorsoModel';
import { Env } from './nitro';
import { loadFigureData } from './figuredata';

const DEFAULT_MALE_FIGURE: string = 'hr-100.hd-180-7.ch-215-66.lg-270-79.sh-305-62.ha-1002-70.wa-2007';
const DEFAULT_FEMALE_FIGURE: string = 'hr-515-33.hd-600-1.ch-635-70.lg-716-66-62.sh-735-68';

export class Editor
{
    figures = new Map<string, FigureData>();
    figureData: FigureData;
    categories: Map<string, any>;
    lastFigure: string; lastGender: string;

    constructor(xml: string, clubLevel: number, config: any = {})
    {
        Env.figureData = loadFigureData(xml);
        Env.clubLevel = clubLevel;
        Env.config = config;
        AvatarEditorUtilities.FIGURE_SET_IDS = [];
        AvatarEditorUtilities.BOUND_FURNITURE_NAMES = [];
        const male = new FigureData(), female = new FigureData();
        male.loadAvatarData(DEFAULT_MALE_FIGURE, FigureData.MALE);
        female.loadAvatarData(DEFAULT_FEMALE_FIGURE, FigureData.FEMALE);
        this.figures.set(FigureData.MALE, male);
        this.figures.set(FigureData.FEMALE, female);
        this.setFigureData(male);
    }

    setFigureData(f: FigureData) { this.figureData = f; AvatarEditorUtilities.CURRENT_FIGURE = f; this.resetCategories(); }

    resetCategories()
    {
        const categories = new Map();
        categories.set(AvatarEditorFigureCategory.GENERIC, new BodyModel());
        categories.set(AvatarEditorFigureCategory.HEAD, new HeadModel());
        categories.set(AvatarEditorFigureCategory.TORSO, new TorsoModel());
        categories.set(AvatarEditorFigureCategory.LEGS, new LegModel());
        // (each makes its categories with model.init() when it's first shown: see model())
        this.categories = categories;
    }

    model(name: string) { const m = this.categories.get(name); m.init(); return m; }

    loadAvatarInEditor(figure: string, gender: string, reset: boolean = true)
    {
        gender = AvatarEditorUtilities.getGender(gender);
        let newFigureData = this.figureData;
        if(gender !== newFigureData.gender) newFigureData = this.figures.get(gender);
        if(figure !== newFigureData.getFigureString()) newFigureData.loadAvatarData(figure, gender);
        if(newFigureData !== this.figureData) this.setFigureData(newFigureData);
        if(reset)
        {
            this.lastFigure = this.figureData.getFigureString();
            this.lastGender = this.figureData.gender;
        }
    }

    clear() { this.loadAvatarInEditor(this.figureData.getFigureStringWithFace(0, false), this.figureData.gender, false); this.resetCategories(); }
    reset() { this.loadAvatarInEditor(this.lastFigure, this.lastGender); this.resetCategories(); }
    randomize()
    {
        const figure = generateRandomFigure(this.figureData, this.figureData.gender, Env.clubLevel, AvatarEditorUtilities.FIGURE_SET_IDS, [ FigureData.FACE ]);
        this.loadAvatarInEditor(figure, this.figureData.gender, false);
        this.resetCategories();
    }
    setGender(gender: string) { this.setFigureData(this.figures.get(AvatarEditorUtilities.getGender(gender))); }

    state()
    {
        const out: any = { figure: this.figureData.getFigureString(), gender: this.figureData.gender, models: {} };
        for(const name of this.categories.keys())
        {
            const m = this.model(name);
            const cats: any = {};
            for(const [ cname, c ] of m.categories.entries())
            {
                cats[cname] = {
                    parts: c.parts.map((p: any) => [ p.id, p.isClear ? 1 : 0, p.isDisabled ? 1 : 0, p.isSelected ? 1 : 0, p.maxColorIndex ]),
                    selected: (c as any)._selectedPartIndex,
                    palettes: [ 0, 1 ].map(i => { const p = c.getPalette(i); return p ? p.map((x: any) => x.partColor.id * 4 + (x.isSelected ? 1 : 0) + (x.isDisabled ? 2 : 0)) : null; }),
                    colorIds: c.getSelectedColorIds(),
                };
            }
            out.models[name] = cats;
        }
        return out;
    }
}
