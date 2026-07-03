// @vitest-environment jsdom
import { render, screen, fireEvent } from '@testing-library/react';
import { SlaegtPicker } from '../SlaegtPicker';

const SLAEGTER = [{ id: 'reventlow', navn: 'Reventlow' }];

describe('SlaegtPicker', () => {
  it('renderer intet når open=false', () => {
    render(<SlaegtPicker open={false} slaegter={SLAEGTER} activeId="reventlow" onClose={vi.fn()} onPick={vi.fn()} />);
    expect(screen.queryByText('Reventlow')).toBeNull();
  });

  it('viser aktiv slægt markeret + "flere kommer"-note', () => {
    render(<SlaegtPicker open={true} slaegter={SLAEGTER} activeId="reventlow" onClose={vi.fn()} onPick={vi.fn()} />);
    expect(screen.getByText('Reventlow')).toBeTruthy();
    expect(screen.getByText(/flere slægter/i)).toBeTruthy();
  });

  it('backdrop-klik lukker', () => {
    const onClose = vi.fn();
    render(<SlaegtPicker open={true} slaegter={SLAEGTER} activeId="reventlow" onClose={onClose} onPick={vi.fn()} />);
    fireEvent.click(screen.getByTestId('slaegt-picker-backdrop'));
    expect(onClose).toHaveBeenCalled();
  });

  it('Escape lukker', () => {
    const onClose = vi.fn();
    render(<SlaegtPicker open={true} slaegter={SLAEGTER} activeId="reventlow" onClose={onClose} onPick={vi.fn()} />);
    fireEvent.keyDown(window, { key: 'Escape' });
    expect(onClose).toHaveBeenCalled();
  });

  it('klik på aktiv slægt kalder onPick', () => {
    const onPick = vi.fn();
    render(<SlaegtPicker open={true} slaegter={SLAEGTER} activeId="reventlow" onClose={vi.fn()} onPick={onPick} />);
    fireEvent.click(screen.getByText('Reventlow'));
    expect(onPick).toHaveBeenCalledWith('reventlow');
  });
});
