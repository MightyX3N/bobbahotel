// Bottom-right, like Habbo's info stand: the furni you clicked, with what you may do with it; and
// while placing or moving a furni, a bar saying so (with Turn and Cancel, for touch screens).
import { actions } from '../actions.ts';
import { t } from '../i18n.ts';
import { useUi } from '../store.ts';

export function FurniInfo() {
  const selected = useUi((s) => s.selectedFurni);
  const placing = useUi((s) => s.placing);
  const me = useUi((s) => s.me);
  const room = useUi((s) => s.room);
  const canEdit = !!me && (me.staff || (room?.ownerId != null && room.ownerId === me.id));

  if (placing) {
    return (
      <div className="infostand">
        <b>{t('furni.placing', { name: placing.name })}</b>
        <span className="infostand-hint">{t(placing.wall ? 'furni.place_hint_wall' : 'furni.place_hint')}</span>
        <div className="infostand-buttons">
          {!placing.wall && (
            <button type="button" className="ui-btn" onClick={() => actions.rotateFurni()}>
              {t('furni.rotate')}
            </button>
          )}
          <button type="button" className="ui-btn" style={{ background: 'var(--btn-close)' }} onClick={() => actions.cancelPlacing()}>
            {t('furni.cancel')}
          </button>
        </div>
      </div>
    );
  }
  if (!selected) return null;
  return (
    <div className="infostand">
      <b>{selected.name}</b>
      {canEdit && (
        <div className="infostand-buttons">
          {!selected.wall && (
            <button type="button" className="ui-btn" onClick={() => actions.rotateFurni()}>
              {t('furni.rotate')}
            </button>
          )}
          <button type="button" className="ui-btn" onClick={() => actions.moveFurni(selected.uid)}>
            {t('furni.move')}
          </button>
          {selected.states > 1 && (
            <button type="button" className="ui-btn" onClick={() => actions.useFurni(selected.uid)}>
              {t('furni.use')}
            </button>
          )}
          <button type="button" className="ui-btn" style={{ background: 'var(--btn-close)' }} onClick={() => actions.pickUpFurni(selected.uid)}>
            {t('furni.pick_up')}
          </button>
        </div>
      )}
    </div>
  );
}
