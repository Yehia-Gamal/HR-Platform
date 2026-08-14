import { Fragment, useEffect } from 'react';
import { MapContainer, TileLayer, Marker, Circle, Popup, useMap } from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import markerIcon from 'leaflet/dist/images/marker-icon.png';
import markerIcon2x from 'leaflet/dist/images/marker-icon-2x.png';
import markerShadow from 'leaflet/dist/images/marker-shadow.png';

// إصلاح أيقونات Leaflet الافتراضية مع أدوات البناء (Vite) — الأصول لا تُحلّ تلقائيًا.
const icon = L.icon({
  iconUrl: markerIcon,
  iconRetinaUrl: markerIcon2x,
  shadowUrl: markerShadow,
  iconSize: [25, 41],
  iconAnchor: [12, 41],
  popupAnchor: [1, -34],
  shadowSize: [41, 41],
});

export type MapPoint = {
  id: string;
  lat: number;
  lng: number;
  accuracy?: number | null;
  label: string;
  sublabel?: string | null;
};

function FitBounds({ points }: { points: MapPoint[] }) {
  const map = useMap();
  useEffect(() => {
    if (!points.length) return;
    if (points.length === 1) {
      map.setView([points[0].lat, points[0].lng], 16);
      return;
    }
    const bounds = L.latLngBounds(points.map((p) => [p.lat, p.lng] as [number, number]));
    map.fitBounds(bounds, { padding: [40, 40], maxZoom: 16 });
  }, [map, points]);
  return null;
}

// خريطة Leaflet/OSM حقيقية (بلا مفتاح API). تعرض الدبابيس + دائرة الدقة.
export function LiveLocationMap({ points, height = 420, showAccuracy = true }: { points: MapPoint[]; height?: number; showAccuracy?: boolean }) {
  const center: [number, number] = points.length ? [points[0].lat, points[0].lng] : [26.8206, 30.8025]; // مركز مصر افتراضيًا

  return (
    <div style={{ height }} className="overflow-hidden rounded-2xl">
      <MapContainer center={center} zoom={points.length ? 13 : 6} style={{ height: '100%', width: '100%' }} scrollWheelZoom>
        <TileLayer
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
          url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
        />
        <FitBounds points={points} />
        {points.map((p) => (
          <Fragment key={p.id}>
            {showAccuracy && typeof p.accuracy === 'number' && p.accuracy > 0 ? (
              <Circle center={[p.lat, p.lng]} radius={p.accuracy} pathOptions={{ color: '#2563eb', fillOpacity: 0.12 }} />
            ) : null}
            <Marker position={[p.lat, p.lng]} icon={icon}>
              <Popup>
                <strong>{p.label}</strong>
                {p.sublabel ? (
                  <>
                    <br />
                    {p.sublabel}
                  </>
                ) : null}
                {typeof p.accuracy === 'number' ? (
                  <>
                    <br />
                    دقة ≈ {Math.round(p.accuracy)} متر
                  </>
                ) : null}
              </Popup>
            </Marker>
          </Fragment>
        ))}
      </MapContainer>
    </div>
  );
}
