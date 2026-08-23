import { Component, ElementRef, OnDestroy, ViewChild, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import cytoscape, { Core } from 'cytoscape';
// eslint-disable-next-line @typescript-eslint/no-var-requires
import dagre from 'cytoscape-dagre';
import { PathApiError, PathApiService, PathNotFoundError } from './path-api.service';

cytoscape.use(dagre);

type BannerKind = 'found' | 'not-found' | '';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [FormsModule],
  templateUrl: './app.html',
  styleUrl: './app.css',
})
export class App implements OnDestroy {
  // État réactif : en Angular zoneless (pas de zone.js dans ce projet), une
  // simple propriété de classe mutée après un `await` ne déclenche PAS de
  // nouveau rendu. Les Signals, eux, le font automatiquement.
  source = '';
  target = '';
  readonly bannerText = signal('');
  readonly bannerKind = signal<BannerKind>('');
  readonly path = signal<string[]>([]);

  @ViewChild('cyContainer') cyContainerRef?: ElementRef<HTMLDivElement>;
  private cy: Core | null = null;

  constructor(private readonly api: PathApiService) {}

  async search(): Promise<void> {
    const source = this.source.trim();
    const target = this.target.trim();

    if (!source || !target) {
      this.setBanner('Renseigne un nœud source et un nœud cible.', 'not-found');
      return;
    }

    this.setBanner('Recherche en cours…', 'found');
    this.path.set([]);
    this.destroyGraph();

    try {
      const result = await this.api.findPath(source, target);
      const hops = result.path.length - 1;
      this.setBanner(`✓ Un chemin existe (${hops} arête${hops > 1 ? 's' : ''}).`, 'found');
      this.path.set(result.path);
      this.renderGraph(result.path);
    } catch (err) {
      if (err instanceof PathNotFoundError) {
        this.setBanner(`✗ Aucun chemin de "${source}" vers "${target}".`, 'not-found');
      } else if (err instanceof PathApiError) {
        this.setBanner(err.message, 'not-found');
      } else {
        this.setBanner("Impossible de contacter l'API.", 'not-found');
      }
    }
  }

  clear(): void {
    this.source = '';
    this.target = '';
    this.path.set([]);
    this.setBanner('', '');
    this.destroyGraph();
  }

  private setBanner(text: string, kind: BannerKind): void {
    this.bannerText.set(text);
    this.bannerKind.set(kind);
  }

  private renderGraph(path: string[]): void {
    const container = this.cyContainerRef?.nativeElement;
    if (!container) return;

    const nodeIds = [...new Set(path)];
    const elements = [
      ...nodeIds.map((id) => ({ data: { id, label: id } })),
      ...path.slice(0, -1).map((id, i) => ({
        data: { id: `${id}->${path[i + 1]}`, source: id, target: path[i + 1] },
      })),
    ];

    this.cy = cytoscape({
      container,
      elements,
      style: [
        {
          selector: 'node',
          style: {
            'background-color': '#4C72B0',
            label: 'data(label)',
            color: '#fff',
            'text-valign': 'center',
            'text-halign': 'center',
            'font-size': 12,
            width: 42,
            height: 42,
          },
        },
        {
          selector: 'edge',
          style: {
            width: 3,
            'line-color': '#16a34a',
            'target-arrow-color': '#16a34a',
            'target-arrow-shape': 'triangle',
            'curve-style': 'bezier',
          },
        },
      ],
      layout: { name: 'dagre', rankDir: 'LR', nodeSep: 30, rankSep: 70 } as cytoscape.LayoutOptions,
    });

    this.cy.$id(path[0]).style('background-color', '#0ea5e9');
    this.cy.$id(path[path.length - 1]).style('background-color', '#f59e0b');
  }

  private destroyGraph(): void {
    this.cy?.destroy();
    this.cy = null;
  }

  ngOnDestroy(): void {
    this.destroyGraph();
  }
}
