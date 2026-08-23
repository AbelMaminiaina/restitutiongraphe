import { HttpClient, HttpErrorResponse } from '@angular/common/http';
import { Injectable } from '@angular/core';
import { catchError, firstValueFrom } from 'rxjs';

// URL du backend C# (PathFinder.Api). Port fixé dans launchSettings.json.
const API_BASE = 'http://127.0.0.1:5065';

export interface PathResult {
  path: string[];
  found: boolean;
}

export class PathNotFoundError extends Error {}
export class PathApiError extends Error {}

@Injectable({ providedIn: 'root' })
export class PathApiService {
  constructor(private readonly http: HttpClient) {}

  async findPath(source: string, target: string): Promise<PathResult> {
    const url = `${API_BASE}/api/path?source=${encodeURIComponent(source)}&target=${encodeURIComponent(target)}`;

    return firstValueFrom(
      this.http.get<PathResult>(url).pipe(
        catchError((err: HttpErrorResponse) => {
          if (err.status === 404) {
            throw new PathNotFoundError(err.error?.detail ?? 'Aucun chemin trouvé.');
          }
          throw new PathApiError(err.error?.detail ?? `Erreur API (${err.status})`);
        }),
      ),
    );
  }
}
